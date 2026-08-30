import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/image_upload.dart';
import '../domain/cover_photo.dart';

/// Nome do bucket. Gêmeo do `storage.buckets.id` criado na migration.
const coverPhotoBucket = 'fotos-capa';

/// Leitura e escrita da capa.
///
/// **Este repositório nunca apaga arquivo.** Ele apaga a *linha*; quem apaga o
/// arquivo é o gatilho `fotos_capa_enfileirar_remocao`, que enfileira, e a
/// drenagem que roda fora da transação. É o núcleo da feature, e a razão é
/// research D-003: a rodada de votação descarta candidatas perdedoras com um
/// `delete from public.acoes` que **não passa por tela nenhuma**. Se a remoção
/// do arquivo morasse aqui, esse caminho jamais apagaria arquivo — e ninguém
/// perceberia, porque órfão não aparece em lugar algum.
class CoverPhotoRepository {
  CoverPhotoRepository(this._client, {Random? random})
      : _random = random ?? Random.secure();

  final SupabaseClient _client;
  final Random _random;

  Future<CoverPhoto?> fetchForGroup(String groupId) =>
      _fetchOne('grupo_id', groupId);

  Future<CoverPhoto?> fetchForAction(String actionId) =>
      _fetchOne('acao_id', actionId);

  Future<CoverPhoto?> _fetchOne(String column, String id) async {
    final row = await _client
        .from('fotos_capa')
        .select()
        .eq(column, id)
        .maybeSingle();
    if (row == null) return null;
    return CoverPhoto.fromMap(row);
  }

  /// As capas de vários Grupos de uma vez, indexadas por `grupo_id`.
  ///
  /// Existe por causa da **lista**. Uma consulta por card seria N consultas
  /// para N Grupos, e — pior — cada card cresceria no momento em que a sua
  /// capa chegasse, que é exatamente o pulo de layout que FR-007 proíbe.
  /// Resolvendo tudo antes de pintar, a lista nasce do tamanho certo.
  Future<Map<String, CoverPhoto>> fetchForGroups(List<String> groupIds) async {
    if (groupIds.isEmpty) return const {};
    final rows = await _client
        .from('fotos_capa')
        .select()
        .inFilter('grupo_id', groupIds);
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['grupo_id'] as String:
            CoverPhoto.fromMap(row),
    };
  }

  /// O mesmo para Ações, e pelo mesmo motivo.
  Future<Map<String, CoverPhoto>> fetchForActions(List<String> actionIds) async {
    if (actionIds.isEmpty) return const {};
    final rows = await _client
        .from('fotos_capa')
        .select()
        .inFilter('acao_id', actionIds);
    return {
      for (final row in rows as List)
        (row as Map<String, dynamic>)['acao_id'] as String:
            CoverPhoto.fromMap(row),
    };
  }

  /// Endereço público da imagem. O bucket é público (FR-008), como o Grupo e a
  /// Ação já são.
  ///
  /// **Depois da remoção, este endereço ainda responde por até 60 segundos** —
  /// é a janela de propagação do cache de borda, medida em fonte primária
  /// (research D-004) e aceita pelo responsável pelo app. A Política de
  /// Privacidade diz isso com essas palavras.
  String publicUrlFor(CoverPhoto photo) => publicUrlForPath(photo.path);

  /// A partir do caminho solto — a tela de denúncias trabalha com o caminho,
  /// não com a linha inteira.
  String publicUrlForPath(String path) =>
      _client.storage.from(coverPhotoBucket).getPublicUrl(path);

  /// Envia a capa de um Grupo. Se já houver uma, ela é **trocada**.
  Future<void> uploadForGroup({
    required String groupId,
    required PickedImage image,
  }) =>
      _upload(ownerPrefix: 'grupo', ownerId: groupId, image: image);

  /// Envia a capa de uma Ação. Se já houver uma, ela é **trocada**.
  Future<void> uploadForAction({
    required String actionId,
    required PickedImage image,
  }) =>
      _upload(ownerPrefix: 'acao', ownerId: actionId, image: image);

  Future<void> _upload({
    required String ownerPrefix,
    required String ownerId,
    required PickedImage image,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Envio de capa exige sessão.');
    }

    final path = _newPath(ownerPrefix, ownerId, image.extension);

    // ORDEM DELIBERADA: sobe o arquivo novo, só então apaga a linha antiga, e
    // por último grava a linha nova.
    //
    // O índice único por Grupo/Ação impede duas linhas ao mesmo tempo, então
    // alguma ordem tinha de ser escolhida. Esta é a que falha melhor: se o
    // upload falhar, nada mudou. A ordem inversa (apagar primeiro) perde a capa
    // do mesmo jeito e ainda deixa uma janela em que a tela mostra capa que já
    // não existe.
    //
    // ================================================================
    // O QUE ESTA ORDEM **NÃO** GARANTE — e quem cobre isso
    // ================================================================
    // Uma versão anterior deste comentário afirmava que uma falha depois do
    // upload "não cria arquivo servido sem linha que o gerencie". Era falso.
    // O arquivo já subiu quando o `delete` e o `insert` abaixo rodam; se
    // qualquer um dos dois falhar — rede caindo, ou duas pessoas que
    // administram o mesmo Grupo enviando ao mesmo tempo e batendo no índice
    // único — o arquivo fica no bucket público sem linha em `fotos_capa` e
    // **sem entrar na fila de remoção**, porque a fila é alimentada pelo
    // gatilho de DELETE de `fotos_capa`, e este arquivo nunca teve linha para
    // apagar.
    //
    // Medido em 2026-08-10: um objeto nesse estado não move a consulta de
    // saúde de INFRA-PRODUCAO.md § 3 — é invisível para o único sinal que o
    // projeto tem.
    //
    // Fechar isso aqui não dá: `capas_a_remover` não tem grant para o app e
    // `storage.objects` não tem policy de delete para ele; e a compensação
    // rodaria no mesmo cliente que acabou de falhar. Quem cobre é a varredura
    // `public.varrer_capas_orfas()`
    // (`supabase/migrations/20260810160000_varredura_capas_orfas.sql`), de hora
    // em hora, com carência de uma hora para não matar upload em andamento.
    //
    // A garantia real, então, é esta: **nenhum arquivo fica no bucket para
    // sempre**; um arquivo órfão pode ficar público por até cerca de duas
    // horas, sem estar referenciado por tela nenhuma.
    // Cada etapa falha com a SUA identidade. Um `try` só em volta das três
    // devolvia um erro indistinguível, e a tela dizia a mesma frase para
    // estados opostos: "nada mudou" e "a capa que existia foi destruída".
    try {
      await _client.storage.from(coverPhotoBucket).uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(contentType: image.mimeType),
          );
    } catch (_) {
      throw const CoverPhotoUploadFailed(CoverPhotoUploadStage.sendingFile);
    }

    // O `.select()` não é enfeite: é como se sabe se havia capa antes. Sem
    // ele, uma falha na etapa seguinte não teria como distinguir "o Grupo
    // continua sem capa" de "o Grupo perdeu a capa que tinha" — e essas duas
    // frases não podem ser a mesma.
    final List<dynamic> removed;
    try {
      removed = await _client
          .from('fotos_capa')
          .delete()
          .eq('${ownerPrefix}_id', ownerId)
          .select() as List<dynamic>;
    } catch (_) {
      throw const CoverPhotoUploadFailed(
        CoverPhotoUploadStage.removingPrevious,
      );
    }

    try {
      await _client.from('fotos_capa').insert({
        '${ownerPrefix}_id': ownerId,
        'caminho': path,
        'enviada_por': userId,
      });
    } catch (_) {
      throw CoverPhotoUploadFailed(
        CoverPhotoUploadStage.savingRecord,
        previousPhotoLost: removed.isNotEmpty,
      );
    }
  }

  /// Remove a capa. Apaga só a linha — o arquivo sai pela fila.
  ///
  /// Zero linhas é recusa: quem não administra o Grupo/Ação não tira a capa, e
  /// a policy responde com ausência, não com erro. Distinguir isso de uma falha
  /// de rede importa para a tela — numa ela não sabe o que aconteceu, na outra
  /// sabe que não aconteceu.
  Future<void> remove(CoverPhoto photo) async {
    final affected =
        await _client.from('fotos_capa').delete().eq('id', photo.id).select('id');
    if (affected.isEmpty) {
      throw StateError('Essa imagem não saiu: você não administra este espaço.');
    }
  }

  /// Cutuca a drenagem da fila. **Nunca lança.**
  ///
  /// É o **segundo gatilho** que a migration da drenagem sempre afirmou ter, e
  /// que não existia: `pg_cron` roda dentro do Postgres, e projeto no plano
  /// gratuito é pausado depois de uma semana sem atividade — com o banco
  /// pausado, o cron para junto. Quem acorda o banco é o app, então é o app que
  /// precisa pedir a drenagem quando mexe na fila. A escolha do plano gratuito
  /// virou decisão registrada na feature 019, o que torna isto menos teórico.
  ///
  /// Engolir a falha é deliberado: a remoção da linha **já aconteceu** quando
  /// isto roda, e derrubá-la aqui transformaria uma limpeza atrasada numa
  /// remoção que a pessoa vê falhar. O atraso tem outro dono — o cron.
  Future<void> requestDrain() async {
    try {
      await _client.rpc('drenar_capas_a_remover');
    } catch (_) {
      // Silêncio proposital. Ver acima.
    }
  }

  /// Caminho **novo e único a cada envio, nunca reaproveitado** (research
  /// D-001).
  ///
  /// Não é preciosismo: com cache de borda, um caminho reaproveitado serve a
  /// imagem **antiga** no endereço novo. É o jeito mais silencioso de a
  /// remoção falhar — a pessoa troca a capa, o app diz que trocou, e quem
  /// olha continua vendo a foto que ela quis tirar do ar.
  ///
  /// Os dois primeiros segmentos são o contrato com a política de
  /// armazenamento (research D-007), que confere o segmento do meio contra
  /// quem administra o Grupo/Ação. Mudar o formato aqui sem mudar a política
  /// faz a escrita passar a valer para qualquer prefixo.
  String _newPath(String ownerPrefix, String ownerId, String extension) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = _random.nextInt(1 << 32).toRadixString(36);
    return '$ownerPrefix/$ownerId/$stamp-$noise.$extension';
  }
}

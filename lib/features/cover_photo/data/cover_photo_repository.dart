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

  /// Endereço público da imagem. O bucket é público (FR-008), como o Grupo e a
  /// Ação já são.
  ///
  /// **Depois da remoção, este endereço ainda responde por até 60 segundos** —
  /// é a janela de propagação do cache de borda, medida em fonte primária
  /// (research D-004) e aceita pelo responsável pelo app. A Política de
  /// Privacidade diz isso com essas palavras.
  String publicUrlFor(CoverPhoto photo) =>
      _client.storage.from(coverPhotoBucket).getPublicUrl(photo.path);

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
    // upload falhar, nada mudou; se a gravação da linha falhar depois do
    // delete, perde-se a capa mas não se cria arquivo servido sem linha que o
    // gerencie. A ordem inversa (apagar primeiro) tem a mesma perda e ainda
    // deixa uma janela em que a tela mostra capa que já não existe.
    await _client.storage.from(coverPhotoBucket).uploadBinary(
          path,
          image.bytes,
          fileOptions: FileOptions(contentType: image.mimeType),
        );

    await _client
        .from('fotos_capa')
        .delete()
        .eq('${ownerPrefix}_id', ownerId);

    await _client.from('fotos_capa').insert({
      '${ownerPrefix}_id': ownerId,
      'caminho': path,
      'enviada_por': userId,
    });
  }

  /// Remove a capa. Apaga só a linha — o arquivo sai pela fila.
  Future<void> remove(CoverPhoto photo) async {
    await _client.from('fotos_capa').delete().eq('id', photo.id);
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

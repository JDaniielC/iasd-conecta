import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/message.dart';
import '../domain/message_report.dart';
import '../domain/send_refusal.dart';

/// Único ponto de acesso a `mensagens` e `denuncias_mensagem`.
///
/// Não há checagem de permissão aqui, e isso é desenho: quem pode ler, escrever,
/// remover e denunciar está nas policies do banco, provado por 29 testes de
/// integração. Repetir a regra no cliente criaria uma segunda cópia dela, e a
/// primeira divergência entre as duas é um bug de privacidade que o teste de
/// banco não pega.
class ChatRepository {
  ChatRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'mensagens';

  /// Quantas mensagens uma página traz.
  static const pageSize = 50;

  /// O histórico de um espaço, mais recente primeiro.
  ///
  /// **Dispara o expurgo de retenção e NÃO espera por ele** (tarefa 7.5). O
  /// prazo de 30 dias tem dois gatilhos: o `pg_cron` e esta chamada. O cron
  /// sozinho não cumpre — no plano gratuito o projeto pausa por inatividade e o
  /// cron para junto, e quem acorda o banco é o app. Logo é o app que precisa
  /// cumprir o prazo.
  ///
  /// `unawaited` de propósito: a pessoa abriu uma conversa para ler, não para
  /// esperar faxina. Se o expurgo falhar ou demorar, o histórico aparece do
  /// mesmo jeito — e a mensagem vencida que escapou desta vez sai na próxima
  /// abertura ou no cron. O erro é engolido pelo mesmo motivo: não há nada que
  /// a pessoa possa fazer a respeito, e um aviso na tela só transformaria uma
  /// faxina atrasada em susto.
  ///
  /// Ordem importa: o expurgo vai ANTES do `await` da consulta, para as duas
  /// idas ao servidor correrem juntas em vez de somar latência.
  Future<List<Message>> fetchHistory({
    String? groupId,
    String? actionId,
    DateTime? before,
  }) async {
    assert(
      (groupId == null) != (actionId == null),
      'exatamente um espaço, como o check mensagens_um_espaco_so',
    );

    unawaited(purgeExpiredActionMessages());

    var query = _client
        .from(_table)
        .select()
        .eq(groupId != null ? 'grupo_id' : 'acao_id', groupId ?? actionId!);
    if (before != null) {
      query = query.lt('created_at', before.toIso8601String());
    }
    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize);

    return _withAuthorNames(rows);
  }

  /// Resolve nome de quem escreveu, uma chamada por AUTOR DISTINTO e não por
  /// linha, concorrentes. Mesmo desenho de `NotificationRepository.fetch` — em
  /// série cada uma esperava a anterior e a latência somava em rede de celular.
  ///
  /// **FALHA DE NOME NÃO DERRUBA A MENSAGEM**, e é a mesma decisão que
  /// [withAuthorName] (singular) já tomava vinte linhas abaixo: sem o nome a
  /// mensagem ainda é legível; sem a mensagem, não. Aqui ela faltava, e o
  /// estrago aparecia no ENVIO.
  ///
  /// `send` são duas idas ao servidor. O `insert` commita sozinho — medido na
  /// convergência 2, a contagem do Grupo foi de 1 para 2 antes de qualquer
  /// passo seguinte. Sem este `catch`, uma falha na resolução do nome subia,
  /// `ChatNotifier.send` propagava, e a tela dizia "Não deu pra enviar agora.
  /// Tente de novo." sobre uma mensagem que JÁ ESTAVA no chat. A pessoa tentava
  /// de novo e levava `PT425 espere 3 segundos` — recusa correta, sobre um
  /// problema que ela não causou. Antes do limite de ritmo o reenvio só
  /// duplicava em silêncio; o limite transformou o defeito invisível em recusa
  /// que ninguém entende.
  ///
  /// O `catch` é POR AUTOR e não em volta do `Future.wait`: um nome que falha
  /// não pode levar junto os nomes que deram certo na mesma leva.
  Future<List<Message>> _withAuthorNames(
    List<Map<String, dynamic>> rows,
  ) async {
    final authorIds = rows.map((r) => r['autor_id'] as String).toSet().toList();
    final resolved = await Future.wait(
      authorIds.map((uid) async {
        try {
          final r =
              await _client.rpc('perfil_publico', params: {'p_id': uid})
                  as List;
          return r.isEmpty
              ? null
              : MapEntry(
                  uid,
                  (r.first as Map<String, dynamic>)['nome_exibido'] as String,
                );
        } catch (_) {
          return null;
        }
      }),
    );
    final names = Map.fromEntries(
      resolved.whereType<MapEntry<String, String>>(),
    );

    return [
      for (final row in rows)
        Message.fromMap(row, authorName: names[row['autor_id']]),
    ];
  }

  /// A pessoa pode ver ESTA conversa? Pergunta ao banco, pela mesma função que
  /// a policy usa.
  ///
  /// Reimplementar o predicado em Dart criaria uma segunda cópia da regra, e a
  /// primeira divergência entre as duas é uma tela que promete o que a policy
  /// nega — ou pior, esconde o que ela permitiria.
  Future<bool> canSeeChat({String? groupId, String? actionId}) async {
    final r = await _client.rpc(
      groupId != null ? 'pode_ver_chat_grupo' : 'pode_ver_chat_acao',
      params: {
        groupId != null ? 'p_grupo_id' : 'p_acao_id': groupId ?? actionId,
      },
    );
    return r as bool? ?? false;
  }

  /// Tem 18 anos ou mais? Separado de [canSeeChat] de propósito: as duas
  /// respostas são `false` do mesmo jeito, e a tela precisa saber QUAL delas
  /// para poder explicar em vez de sumir sem dizer nada.
  Future<bool> isOfAge() async {
    final r = await _client.rpc('maior_de_idade');
    return r as bool? ?? false;
  }

  /// Uma linha crua do canal de tempo real, com o nome de quem escreveu.
  ///
  /// O payload do Realtime traz a linha inteira menos o nome — ele não existe
  /// em `mensagens`, é resolvido por `perfil_publico`. Uma chamada por mensagem
  /// nova, que é o custo certo: mensagem nova chega uma de cada vez.
  Future<Message> withAuthorName(Map<String, dynamic> row) async {
    final uid = row['autor_id'] as String;
    try {
      final r =
          await _client.rpc('perfil_publico', params: {'p_id': uid}) as List;
      return Message.fromMap(
        row,
        authorName: r.isEmpty
            ? null
            : (r.first as Map<String, dynamic>)['nome_exibido'] as String,
      );
    } catch (_) {
      // Sem o nome a mensagem ainda é legível; sem a mensagem, não. Sumir com
      // a frase porque a resolução do nome falhou seria perder o que importa
      // para preservar o enfeite.
      return Message.fromMap(row);
    }
  }

  /// Escreve. O autor é a sessão corrente — mandar `autor_id` daqui seria
  /// escrever um valor que a policy `mensagens_insert_autor` confere de novo.
  /// Devolve a linha inserida, e é isso que faz a mensagem própria aparecer
  /// sem depender do canal. A alternativa — esperar o evento voltar — some com
  /// a frase de quem escreveu quando o tempo real está caído: o campo limpa, o
  /// `insert` dá certo, e nada é desenhado. Ver a decisão "Quem manda na lista
  /// da conversa" no design.
  Future<Message> send({
    String? groupId,
    String? actionId,
    required String text,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('é preciso ter sessão para escrever');

    final rows = await _refusalAware(
      () => _client.from(_table).insert({
        'grupo_id': groupId,
        'acao_id': actionId,
        'autor_id': uid,
        'texto': text,
      }).select(),
    );

    return _withAuthorNames(rows).then((list) => list.single);
  }

  /// Roda [write] e troca a exceção crua do Supabase pela recusa que a tela
  /// sabe explicar — quando ela é uma das três desta feature.
  ///
  /// **O ÚNICO lugar do cliente que conhece `PostgrestException` nestas três
  /// recusas.** `SendRefusal` é Dart puro para poder ser provado em `dart test`
  /// contra o PostgREST de verdade (`test/integration/limites_de_chat_test.dart`),
  /// fora do Flutter; o desembrulho fica aqui, onde o pacote do Supabase já é
  /// dependência.
  ///
  /// O que não é uma das três sobe como estava: falta de rede, recusa de policy
  /// e violação de `check` continuam sendo "não deu pra enviar agora", e devem
  /// continuar — inventar explicação para elas seria pior do que a frase
  /// genérica.
  Future<T> _refusalAware<T>(Future<T> Function() write) async {
    try {
      return await write();
    } on PostgrestException catch (error) {
      final refusal = SendRefusal.fromCode(error.code, error.hint);
      if (refusal != null) throw refusal;
      rethrow;
    }
  }

  /// Remove. É `update`, não `delete` — não existe policy de `delete` em
  /// `mensagens` para papel nenhum, e apagar de verdade é só do expurgo.
  ///
  /// O texto removido não é guardado em lugar nenhum. Quem remove precisa ler
  /// antes, porque depois não dá para reconsiderar.
  /// `.select()` no fim NÃO é adorno: recusa de RLS num `update` é ZERO LINHA,
  /// não erro. Sem ele, quem não pode remover recebia sucesso e a tela dizia
  /// que a mensagem saiu — enquanto ela continuava lá para todo mundo. Foi
  /// exatamente assim que o Administrador do distrito "removia" mensagem de
  /// Ação por semanas sem remover nada. A policy é a autoridade; este método
  /// só precisa parar de mentir quando ela recusa.
  Future<void> removeMessage(String messageId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('é preciso ter sessão para remover');

    final affected = await _client
        .from(_table)
        .update({
          'texto': null,
          'removida_em': DateTime.now().toUtc().toIso8601String(),
          'removida_por': uid,
        })
        .eq('id', messageId)
        .select();

    if (affected.isEmpty) {
      throw StateError('esta mensagem não pôde ser removida por você');
    }
  }

  /// As mensagens FIXADAS daquele espaço, mais recente primeiro.
  ///
  /// **Consulta separada, e a decisão foi MEDIDA** (tarefa 5.4). Com 2000
  /// mensagens no chat e as três fixadas sendo as mais antigas de todas, num
  /// Postgres local:
  ///
  ///   página de histórico sozinha ......... 0,023 ms
  ///   fixadas sozinhas (índice parcial) ... 0,006 ms
  ///   as duas em `union` numa consulta .... 0,048 ms
  ///
  /// O `union` é mais CARO que as duas somadas — ele paga um `HashAggregate`
  /// para deduzir as fixadas que já vieram na página. E, no PostgREST, `union`
  /// não existe: sairia numa função `security definer` nova, com grant novo e
  /// superfície nova, para ficar mais lento.
  ///
  /// Por que não basta separar em memória o que o histórico já trouxe: uma
  /// fixada ANTIGA está fora da primeira página. Era o caso da medição, e é o
  /// caso que dá sentido à faixa — o que se fixa é justamente o que ia afundar.
  ///
  /// Quem chama dispara esta junto com [fetchHistory], não depois: são duas
  /// idas ao servidor que correm em paralelo, então a segunda não soma latência.
  Future<List<Message>> fetchPinned({String? groupId, String? actionId}) async {
    assert(
      (groupId == null) != (actionId == null),
      'exatamente um espaço, como o check mensagens_um_espaco_so',
    );

    final rows = await _client
        .from(_table)
        .select()
        .eq(groupId != null ? 'grupo_id' : 'acao_id', groupId ?? actionId!)
        .not('fixada_em', 'is', null)
        .order('fixada_em', ascending: false);

    return _withAuthorNames(rows);
  }

  /// Fixa. `fixada_por` é a sessão corrente porque o gatilho RECUSA outro
  /// valor — carimbar por cima seria ignorar em silêncio o que o cliente
  /// mandou, e o banco preferiu recusar.
  ///
  /// `.select()` no fim pela regra desta base: recusa de RLS num `update` é
  /// ZERO LINHA, não erro. Quem não passa pela policy — participante comum —
  /// receberia sucesso sobre nada, e a faixa apareceria vazia sem explicação.
  /// Quem passa pela policy e é barrado pelo GATILHO — o autor sem autoridade,
  /// e o teto — recebe exceção com `errcode`, e é o `_refusalAware` que a
  /// traduz. As duas formas de recusa existem, e esta função trata as duas.
  Future<void> pinMessage(String messageId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('é preciso ter sessão para fixar');

    final affected = await _refusalAware(
      () => _client
          .from(_table)
          .update({
            'fixada_em': DateTime.now().toUtc().toIso8601String(),
            'fixada_por': uid,
          })
          .eq('id', messageId)
          .select(),
    );

    if (affected.isEmpty) {
      throw StateError('esta mensagem não pôde ser fixada por você');
    }
  }

  /// Desfixa. Autoridade do espaço **ou** o autor da mensagem — e o braço do
  /// autor é o que devolve a ele o controle do prazo do que escreveu: fixada
  /// não expira, e sem este caminho o prazo dele dependeria de outra pessoa
  /// indefinidamente.
  ///
  /// As duas colunas vão juntas: `mensagens_fixada_completa` recusa uma sem a
  /// outra.
  Future<void> unpinMessage(String messageId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('é preciso ter sessão para desfixar');

    final affected = await _client
        .from(_table)
        .update({'fixada_em': null, 'fixada_por': null})
        .eq('id', messageId)
        .select();

    if (affected.isEmpty) {
      throw StateError('esta mensagem não pôde ser desfixada por você');
    }
  }

  /// Denuncia. O `motivo` escrito aqui é o que fica como registro do caso —
  /// o texto denunciado não é conservado.
  ///
  /// O MESMO filtro de palavra do chat vale aqui. Sem ele o campo de denúncia
  /// vira a via aberta que o chat deixou de ser — e ele é lido por quem modera.
  /// Não há limite de ritmo em denúncia: denunciar não é conversar, e um limite
  /// aqui protegeria quem está sendo denunciado.
  Future<void> reportMessage(String messageId, String reason) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('é preciso ter sessão para denunciar');

    await _refusalAware(
      () => _client.from('denuncias_mensagem').insert({
        'mensagem_id': messageId,
        'motivo': reason,
        'denunciante_id': uid,
      }),
    );
  }

  /// Manda no espaço? `pode_moderar_espaco`, a mesma função das policies de
  /// denúncia — e ela NÃO inclui o autor da mensagem, de propósito: o
  /// denunciado é parte, não instância.
  Future<bool> canModerateSpace({String? groupId, String? actionId}) async {
    final r = await _client.rpc(
      'pode_moderar_espaco',
      params: {'p_grupo_id': groupId, 'p_acao_id': actionId},
    );
    return r as bool? ?? false;
  }

  /// As denúncias daquele espaço, pela função do banco.
  ///
  /// Chama `denuncias_do_espaco` em vez de montar o filtro aqui, e a diferença
  /// não é estilo: quando o espaço é um Grupo, pertencem a ele também as
  /// denúncias dos chats das **Ações daquele Grupo**. A versão anterior
  /// filtrava `mensagens.grupo_id` por embed `!inner`, e denúncia de chat de
  /// Ação tem esse campo nulo — sumia da tela do Dono sem nada indicar que
  /// faltava. Medido na convergência 1.
  ///
  /// A RLS continua decidindo QUEM vê; a função decide O QUE pertence ao espaço.
  ///
  /// LIMITE CONHECIDO, consequência do `on delete set null`: depois do expurgo a
  /// denúncia perde o vínculo com a mensagem, e sem vínculo não há como saber de
  /// que espaço ela era. Denúncia `sem_mensagem` não aparece aqui — sai por
  /// [fetchOrphanReports].
  Future<List<MessageReport>> fetchReports({
    String? groupId,
    String? actionId,
  }) async {
    final rows =
        await _client.rpc(
              'denuncias_do_espaco',
              params: {'p_grupo_id': groupId, 'p_acao_id': actionId},
            )
            as List;

    return [
      for (final row in rows)
        ?MessageReport.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// As denúncias que PERDERAM a mensagem — expurgo dos 30 dias.
  ///
  /// Existem separadas porque não têm espaço: `on delete set null` levou o
  /// vínculo, e sem vínculo não dá para dizer de que Grupo ou Ação eram. A
  /// função `denuncias_do_espaco` junta com `mensagens` e por isso não as
  /// alcança.
  ///
  /// Sem este caminho, a linha sobrevivia no banco e NINGUÉM a lia — a
  /// migration e a Política afirmavam que a denúncia não some sem desfecho, e
  /// o desfecho `sem_mensagem` era um ramo morto na tela. Achado pelo agente
  /// `promessa-vs-execucao` no fechamento da change.
  ///
  /// A RLS decide quem vê: o braço de Administrador do distrito em
  /// `denuncias_mensagem_select_autoridade` não depende da junção com
  /// `mensagens`, então é ele — e só ele — quem alcança estas.
  Future<List<MessageReport>> fetchOrphanReports() async {
    // Colunas NOMEADAS, e `denunciante_id` fica de fora. `select()` sem lista
    // trazia a linha inteira, e a spec diz que a denúncia não revela a quem a
    // lê quem denunciou. O modelo não expunha o campo, mas ele saía do banco
    // assim mesmo. `denuncias_do_espaco` já fazia o certo; agora as duas
    // concordam.
    final rows = await _client
        .from('denuncias_mensagem')
        .select('id, motivo, estado, created_at, resolvida_em, mensagem_id')
        .isFilter('mensagem_id', null)
        .order('created_at', ascending: false);

    return [for (final row in rows) ?MessageReport.fromMap(row)];
  }

  /// Dá desfecho. `mensagem_removida` ou `improcedente` — `sem_mensagem` é do
  /// gatilho do expurgo, não de gente.
  Future<void> resolveReport(String reportId, MessageReportState state) async {
    assert(
      state == MessageReportState.messageRemoved ||
          state == MessageReportState.dismissed,
      'só há dois desfechos que uma pessoa decide',
    );
    // `.select()` no fim pela MESMA razão de `removeMessage`, e esta é a
    // terceira vez que a razão aparece nesta feature: no Postgres, recusa de
    // RLS num `update` é AUSÊNCIA de linha, não exceção. Sem olhar o
    // resultado, este método devolvia sucesso, a lista recarregava, e o caso
    // voltava `pendente` sem uma palavra de explicação.
    final affected = await _client
        .from('denuncias_mensagem')
        .update({
          'estado': state.key,
          'resolvida_em': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reportId)
        .select();

    if (affected.isEmpty) {
      throw StateError('esta denúncia não pôde ser resolvida por você');
    }
  }

  /// O segundo gatilho do prazo de 30 dias. Ver [fetchHistory].
  ///
  /// Devolve quantas linhas foram apagadas — número GLOBAL, de todas as Ações
  /// vencidas, não só a que a pessoa abriu. Ninguém precisa dele hoje; existe
  /// porque uma função de faxina que não diz quanto fez é impossível de
  /// diagnosticar quando o prazo parecer não estar sendo cumprido.
  Future<int> purgeExpiredActionMessages() async {
    try {
      final r = await _client.rpc('expurgar_mensagens_de_acao');
      return r as int? ?? 0;
    } catch (_) {
      // Faxina que falha não estraga a leitura. Ver [fetchHistory].
      return 0;
    }
  }
}

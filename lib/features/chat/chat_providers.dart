import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'data/chat_repository.dart';
import 'domain/chat_state.dart';
import 'domain/message.dart';
import 'domain/message_report.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(supabaseClientProvider));
});

/// De qual espaço é a conversa. Exatamente um dos dois é não nulo, como o
/// `check mensagens_um_espaco_so` do banco.
class ChatSpace {
  const ChatSpace.group(String this.groupId) : actionId = null;
  const ChatSpace.action(String this.actionId) : groupId = null;

  final String? groupId;
  final String? actionId;

  String get column => groupId != null ? 'grupo_id' : 'acao_id';
  String get id => (groupId ?? actionId)!;

  @override
  bool operator ==(Object other) =>
      other is ChatSpace &&
      other.groupId == groupId &&
      other.actionId == actionId;

  @override
  int get hashCode => Object.hash(groupId, actionId);
}

/// A conversa de um espaço: histórico + páginas anteriores + novidade + o que
/// a pessoa acabou de escrever, resolvidos numa lista só.
///
/// **UMA COSTURA, e é o ponto desta classe.** A regra do design — "sobreposição
/// local existe para o que o servidor ainda não disse, e é descartada assim que
/// ele diz" — estava escrita e implementada num lugar só, o `build` da tela. A
/// lista se compunha em quatro lugares, e a convergência 5 mediu três em que a
/// cópia local ganhava do servidor: remover com o canal caído deixava o texto na
/// tela de quem removeu; reconectar descartava a remoção ocorrida durante a
/// queda; e o expurgo não alcançava as páginas antigas, que moravam no widget.
///
/// Agora tudo o que o servidor diz entra por [_applyServer] ou [_forgetRow], e
/// tudo o que é local mora em [_pending]. A tela não junta nada.
///
/// **O canal aqui carrega DADO, não sinal** — diferença deliberada em relação a
/// `notificationSignalProvider`, que reconsulta a cada evento. Lá o filtro de
/// "aviso ainda válido" mora numa view e não cabe num payload; aqui a linha de
/// `mensagens` É a mensagem, e reconsultar a conversa inteira a cada frase dita
/// seria uma ida ao servidor por palavra em Grupo ativo. A RLS no canal é o que
/// torna isso seguro, e ela é provada por teste com sessões reais em
/// `chat_realtime_test.dart` — não por revisão.
///
/// O que o payload NÃO traz é o nome de quem escreveu: `perfil_publico` resolve
/// isso numa chamada por mensagem nova. Nunca por `select` direto em `perfis` —
/// é `perfil_publico` que devolve o Apelido no lugar do nome de menor de idade.
class ChatNotifier extends AsyncNotifier<ChatState> {
  ChatNotifier(this.space);

  final ChatSpace space;

  /// O que o servidor disse: histórico, páginas anteriores e eventos do canal.
  var _server = <Message>[];

  /// As fixadas, por id. Lista PRÓPRIA e não um filtro sobre [_server]: a
  /// fixada antiga está fora da primeira página do histórico, e é ela que dá
  /// sentido à faixa. Ver `ChatState.pinned`.
  final _pinned = <String, Message>{};

  /// O que esta pessoa escreveu e o servidor ainda não devolveu por nenhum
  /// caminho. Some assim que ele fala da linha — inclusive quando falar dela
  /// para dizer que ela não existe mais.
  final _pending = <Message>[];

  var _connection = ChatConnection.reconnecting;
  var _hasMoreOlder = true;
  var _loadingOlder = false;
  var _everSubscribed = false;
  var _built = false;

  @override
  Future<ChatState> build() async {
    final client = ref.watch(supabaseClientProvider);

    // Sem sessão não há canal a abrir. O histórico também não vem — a policy
    // exige `authenticated` —, então o estado honesto é `offline`.
    if (client.auth.currentUser == null) {
      _connection = ChatConnection.offline;
      _built = true;
      return _compose();
    }

    _openChannel(client);

    // As duas consultas correm JUNTAS, não em série: são duas idas ao servidor
    // independentes, e somar a latência delas seria pagar duas vezes por uma
    // tela só. A das fixadas traz no máximo 3 linhas, por índice parcial.
    //
    // Falha de qualquer uma NÃO derruba a conversa: o canal pode estar de pé, e
    // uma conversa que aparece pela metade é melhor do que uma tela de erro.
    final history = _orEmpty(
      () => _repository.fetchHistory(
        groupId: space.groupId,
        actionId: space.actionId,
      ),
    );
    final pinned = _orEmpty(
      () => _repository.fetchPinned(
        groupId: space.groupId,
        actionId: space.actionId,
      ),
    );

    _server = mergeMessages(await history, _server);
    _rememberPinned(await pinned);

    _built = true;
    return _compose();
  }

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// Roda a consulta e devolve lista vazia se ela falhar — inclusive se falhar
  /// ANTES de virar `Future`. Um `catchError` na `Future` não pegaria isso, e a
  /// falha síncrona derrubaria a tela inteira por causa de uma das duas
  /// consultas.
  Future<List<Message>> _orEmpty(Future<List<Message>> Function() query) async =>
      await _orNull(query) ?? const [];

  /// A consulta, ou **nulo se ela falhar** — inclusive se falhar antes de
  /// virar `Future`. Quem precisa distinguir falha de resultado vazio usa esta;
  /// quem não precisa usa [_orEmpty].
  Future<List<Message>?> _orNull(Future<List<Message>> Function() query) async {
    try {
      return await query();
    } catch (_) {
      return null;
    }
  }

  /// A ÚNICA regra de precedência da tela: o servidor vence a sobreposição
  /// local. `mergeMessages` decide entre duas versões da MESMA linha pela
  /// lápide, que é absorvente — ver o comentário lá.
  ChatState _compose() => ChatState(
    messages: mergeMessages(_pending, _server),
    connection: _connection,
    // Mais recente primeiro: a última fixada é a que a pessoa acabou de
    // decidir que importa, e é a que fica no alto da faixa.
    pinned: _pinned.values.toList()
      ..sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!)),
    hasMoreOlder: _hasMoreOlder,
    loadingOlder: _loadingOlder,
  );

  /// O servidor falou destas linhas — a faixa passa a refletir o que ele disse.
  ///
  /// Vale para os DOIS sentidos: a linha que chega fixada entra, e a que chega
  /// sem fixação sai. É por aqui que a lápide deixa a faixa sozinha — o gatilho
  /// do banco desfixa quem perde o texto, e o evento do canal traz a linha já
  /// sem `fixada_em`.
  void _rememberPinned(Iterable<Message> rows) {
    for (final row in rows) {
      if (row.isPinned) {
        _pinned[row.id] = row;
      } else {
        _pinned.remove(row.id);
      }
    }
  }

  void _publish() {
    // Durante o `build` não há estado a publicar ainda; o retorno dele publica.
    if (_built) state = AsyncData(_compose());
  }

  /// O servidor falou destas linhas. Elas entram, e a sobreposição local
  /// correspondente sai — o que ele disse é o que vale.
  void _applyServer(Iterable<Message> rows) {
    _server = mergeMessages(_server, rows);
    _rememberPinned(rows);
    final said = rows.map((m) => m.id).toSet();
    _pending.removeWhere((m) => said.contains(m.id));
    _publish();
  }

  /// O servidor disse que a linha não existe mais — expurgo dos 30 dias. Some
  /// das DUAS listas: enquanto a sobreposição local sobrevivia, a mensagem
  /// expurgada continuava legível na tela de quem tinha paginado.
  void _forgetRow(String id) {
    _server = _server.where((m) => m.id != id).toList();
    _pending.removeWhere((m) => m.id == id);
    _pinned.remove(id);
    _publish();
  }

  void _openChannel(SupabaseClient client) {
    final channel = client
        .channel('chat-${space.column}-${space.id}')
        .onPostgresChanges(
          // `all` e não `insert`: a remoção é um `update`, e sem ela a mensagem
          // removida continuaria com texto na tela de quem estava com o chat
          // aberto — justamente a pessoa de quem se quis tirar o texto.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mensagens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: space.column,
            value: space.id,
          ),
          callback: (payload) async {
            // `delete` chega com `newRecord` VAZIO — é o expurgo dos 30 dias
            // apagando a linha. Ignorá-lo deixava a mensagem na tela de quem
            // estava com a conversa aberta, com o texto que a Política acabara
            // de dizer que não existe mais.
            if (payload.newRecord.isEmpty) {
              final goneId = payload.oldRecord['id'] as String?;
              if (goneId != null) _forgetRow(goneId);
              return;
            }
            final row = await _repository.withAuthorName(payload.newRecord);

            // `update` DE LINHA QUE ESTA TELA NÃO CONHECE só alimenta a faixa.
            //
            // Achado na convergência 3, e medido: `mergeMessages` ACRESCENTA id
            // desconhecido — página de 3 recentes mais uma linha de três meses
            // atrás devolve `[antiga, recente0, recente1, recente2]`. O canal
            // filtra por espaço e não por tempo, então desfixar mensagem antiga
            // entrega o `update` dela a quem nunca paginou até lá.
            //
            // O estrago não é a mensagem aparecer fora de contexto — é o cursor:
            // [loadOlder] pede a página seguinte a partir de
            // `messages.first.createdAt`, que passaria a ser três meses atrás, e
            // todo o histórico intermediário sairia de alcance. Pior, a página
            // vazia que voltasse desligaria o botão de vez.
            //
            // `insert` continua entrando: mensagem nova é justamente a linha que
            // esta tela ainda não conhece, e ela pertence ao fim da conversa.
            // A distinção é entre "ainda não conheço porque acabou de nascer" e
            // "não conheço porque está fora da página".
            if (payload.eventType == PostgresChangeEvent.update &&
                !_server.any((m) => m.id == row.id) &&
                !_pending.any((m) => m.id == row.id)) {
              _rememberPinned([row]);
              _publish();
              return;
            }

            _applyServer([row]);
          },
        )
        .subscribe((status, _) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              // RECONEXÃO REFAZ A CONSULTA, e é o que fecha o buraco: entre a
              // queda e a volta, o canal não entregou nada, e ninguém avisa o
              // que passou. Sem isto, a conversa fica com um vão que só some
              // quando a pessoa fecha e reabre a tela — e ela não tem como
              // saber que precisa.
              if (_everSubscribed) unawaited(_reloadRecent());
              _everSubscribed = true;
              _connection = ChatConnection.live;
            case RealtimeSubscribeStatus.closed:
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
              // `reconnecting` e não `offline`: o cliente do Supabase tenta
              // voltar sozinho. Dizer "sem tempo real" na primeira falha faria
              // a tela desmentir a si mesma segundos depois.
              _connection = ChatConnection.reconnecting;
          }
          _publish();
        });

    // Canal aberto sem fechar vaza conexão, e o plano contratado tem teto de
    // conexões concorrentes.
    ref.onDispose(() async {
      _built = false;
      await client.removeChannel(channel);
    });
  }

  /// Refaz as consultas de abertura. Usada na volta do canal.
  ///
  /// A versão que veio do servidor AGORA vale sobre a que estava na tela desde
  /// antes da queda, e quem garante isso é a lápide absorvente de
  /// `mergeMessages` — não a ordem dos argumentos. Enquanto a ordem decidia,
  /// esta chamada trazia a remoção ocorrida durante a queda e a descartava.
  ///
  /// **AS FIXADAS TAMBÉM**, e esta metade faltava (convergência 1 de
  /// `mensagem-fixada`). O histórico traz a fixação das linhas que estão na
  /// página; a fixada ANTIGA — fora dela, que é o caso que motivou
  /// `fetchPinned` existir — só vem por aqui. Sem isto, fixar ou desfixar
  /// durante a queda não aparecia na faixa até a pessoa fechar e reabrir a
  /// tela, e ela não tem como saber que precisa.
  Future<void> _reloadRecent() async {
    final history = _orEmpty(
      () => _repository.fetchHistory(
        groupId: space.groupId,
        actionId: space.actionId,
      ),
    );
    // NULO É "A CONSULTA FALHOU", e é diferente de "não há fixada nenhuma".
    // Aqui a distinção decide: a faixa é REFEITA a partir desta lista — a
    // fixada que sumiu durante a queda precisa sair, e `_rememberPinned`
    // sozinho só sabe entrar. Tratar falha como lista vazia esvaziaria a faixa
    // por causa de uma consulta que não voltou, que é o defeito, não o
    // conserto. No `build` a diferença não existe: lá não há faixa na tela
    // ainda.
    final pinned = _orNull(
      () => _repository.fetchPinned(
        groupId: space.groupId,
        actionId: space.actionId,
      ),
    );

    _applyServer(await history);

    final rows = await pinned;
    if (rows != null) {
      _pinned
        ..clear()
        ..addEntries(
          rows.where((m) => m.isPinned).map((m) => MapEntry(m.id, m)),
        );
      _publish();
    }
  }

  /// Escreve, e a mensagem aparece na hora — sem depender do canal.
  ///
  /// A linha inserida entra como sobreposição local, e sai assim que o servidor
  /// falar dela por qualquer caminho. Sem isto, enviar com o canal caído limpava
  /// o campo e não desenhava nada: o `insert` dava certo, e só o canal
  /// desenharia o resultado.
  Future<void> send(String text) async {
    final sent = await _repository.send(
      groupId: space.groupId,
      actionId: space.actionId,
      text: text,
    );
    _pending.add(sent);
    _publish();
  }

  /// Remove, e a lápide aparece na hora — sem depender do canal.
  ///
  /// O `update` ter afetado linha é o servidor dizendo que a remoção aconteceu
  /// (`removeMessage` lança quando afeta zero, porque recusa de RLS é ausência,
  /// não erro). Aplicá-lo aqui é registrar o que o servidor disse, não adivinhar
  /// — e é o que faltava: com o canal caído, quem removia continuava vendo o
  /// próprio texto na tela, sem erro e sem lápide.
  Future<void> remove(String messageId) async {
    await _repository.removeMessage(messageId);

    // Procura nas DUAS listas. Em `_pending` mora a mensagem que a pessoa
    // acabou de escrever e cujo eco o canal ainda não trouxe — e remover
    // logo depois de escrever é justamente o caminho que a sobreposição local
    // criou. Sem olhar lá, a lápide saía com `authorId` vazio e `createdAt`
    // de agora: ela mudava de lugar na conversa e aparecia assinada por
    // "Alguém". Medido na convergência 6.
    final current =
        _server.where((m) => m.id == messageId).firstOrNull ??
        _pending.where((m) => m.id == messageId).firstOrNull;

    _applyServer([
      Message(
        id: messageId,
        // Se nem `_pending` tem a linha, ela não está na tela desta pessoa e o
        // que se compõe aqui não é desenhado — o `??` é o piso, não o caso.
        authorId: current?.authorId ?? '',
        createdAt: current?.createdAt ?? DateTime.now().toUtc(),
        groupId: space.groupId,
        actionId: space.actionId,
        removedAt: DateTime.now().toUtc(),
        authorName: current?.authorName,
      ),
    ]);
  }

  /// Fixa, e a faixa muda na hora — sem depender do canal.
  ///
  /// Mesmo desenho de [remove], e pelo mesmo motivo: `pinMessage` lança quando
  /// o `update` afeta zero linhas, então chegar aqui É o servidor dizendo que a
  /// fixação aconteceu. Aplicá-lo é registrar o que ele disse, não adivinhar.
  ///
  /// A recusa de TETO sobe como `SendRefusal` e a tela a explica — ela não é
  /// falha, é o limite fazendo o trabalho dele.
  Future<void> pin(String messageId) async {
    await _repository.pinMessage(messageId);

    final current = _find(messageId);
    if (current == null) return;
    _applyServer([
      current.withPin(
        at: DateTime.now().toUtc(),
        by: ref.read(supabaseClientProvider).auth.currentUser?.id,
      ),
    ]);
  }

  /// Desfixa. Autoridade do espaço **ou** o autor — é o que devolve a ele o
  /// controle do prazo do que escreveu.
  Future<void> unpin(String messageId) async {
    await _repository.unpinMessage(messageId);

    // Da faixa sai sempre, inclusive quando a linha não está na conversa
    // desenhada: fixada antiga vive na faixa e fora da página.
    _pinned.remove(messageId);
    final current = _find(messageId);
    if (current != null) _applyServer([current.withPin()]);
    _publish();
  }

  /// A versão mais completa da linha que esta tela conhece. Procura nas TRÊS
  /// listas: a fixada antiga não está em `_server`, e a recém-escrita ainda
  /// está só em `_pending`.
  Message? _find(String messageId) =>
      _server.where((m) => m.id == messageId).firstOrNull ??
      _pending.where((m) => m.id == messageId).firstOrNull ??
      _pinned[messageId];

  /// Carrega a página anterior. `pageSize` é página, não teto: chat de Grupo não
  /// expira, e sem isto a 51ª mensagem empurrava a 1ª para fora do alcance
  /// permanentemente.
  Future<void> loadOlder() async {
    if (_loadingOlder || !_hasMoreOlder) return;
    final oldest = _compose().messages.firstOrNull;
    if (oldest == null) return;

    _loadingOlder = true;
    _publish();
    try {
      final page = await _repository.fetchHistory(
        groupId: space.groupId,
        actionId: space.actionId,
        before: oldest.createdAt,
      );
      // Página vazia é o fim do histórico.
      _hasMoreOlder = page.isNotEmpty;
      _applyServer(page);
    } finally {
      _loadingOlder = false;
      _publish();
    }
  }
}

final chatProvider = AsyncNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, ChatSpace>(ChatNotifier.new);

/// Tem 18 anos ou mais, segundo o BANCO.
///
/// Não deriva de `myProfileProvider.age`: a idade do Perfil é o que a pessoa
/// digitou, e o corte quem aplica é `maior_de_idade()`. Perguntar ao banco é o
/// que faz a tela e a policy nunca discordarem.
final isOfAgeProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(chatRepositoryProvider).isOfAge();
});

/// Pode ver a conversa deste espaço?
final canSeeChatProvider = FutureProvider.autoDispose.family<bool, ChatSpace>((
  ref,
  space,
) {
  return ref
      .watch(chatRepositoryProvider)
      .canSeeChat(groupId: space.groupId, actionId: space.actionId);
});

/// Manda no espaço? É o que decide se a lista de denúncias aparece.
final canModerateSpaceProvider = FutureProvider.autoDispose
    .family<bool, ChatSpace>((ref, space) {
      return ref
          .watch(chatRepositoryProvider)
          .canModerateSpace(groupId: space.groupId, actionId: space.actionId);
    });

/// As denúncias daquele espaço.
final messageReportsProvider = FutureProvider.autoDispose
    .family<List<MessageReport>, ChatSpace>((ref, space) {
      return ref
          .watch(chatRepositoryProvider)
          .fetchReports(groupId: space.groupId, actionId: space.actionId);
    });

/// As denúncias que perderam a mensagem no expurgo. Sem espaço, por isso
/// separadas — ver `ChatRepository.fetchOrphanReports`.
final orphanMessageReportsProvider =
    FutureProvider.autoDispose<List<MessageReport>>((ref) {
      return ref.watch(chatRepositoryProvider).fetchOrphanReports();
    });

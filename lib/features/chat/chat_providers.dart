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

    // Falha de histórico NÃO derruba a conversa: o canal pode estar de pé, e
    // uma conversa que aparece pela metade é melhor do que uma tela de erro.
    try {
      _server = mergeMessages(
        await _repository.fetchHistory(
          groupId: space.groupId,
          actionId: space.actionId,
        ),
        _server,
      );
    } catch (_) {
      // Sem histórico, o canal ainda pode falar. A tela desenha o que houver.
    }

    _built = true;
    return _compose();
  }

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// A ÚNICA regra de precedência da tela: o servidor vence a sobreposição
  /// local. `mergeMessages` decide entre duas versões da MESMA linha pela
  /// lápide, que é absorvente — ver o comentário lá.
  ChatState _compose() => ChatState(
    messages: mergeMessages(_pending, _server),
    connection: _connection,
    hasMoreOlder: _hasMoreOlder,
    loadingOlder: _loadingOlder,
  );

  void _publish() {
    // Durante o `build` não há estado a publicar ainda; o retorno dele publica.
    if (_built) state = AsyncData(_compose());
  }

  /// O servidor falou destas linhas. Elas entram, e a sobreposição local
  /// correspondente sai — o que ele disse é o que vale.
  void _applyServer(Iterable<Message> rows) {
    _server = mergeMessages(_server, rows);
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
            _applyServer([await _repository.withAuthorName(payload.newRecord)]);
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

  /// Refaz a consulta das mais recentes. Usada na volta do canal.
  ///
  /// A versão que veio do servidor AGORA vale sobre a que estava na tela desde
  /// antes da queda, e quem garante isso é a lápide absorvente de
  /// `mergeMessages` — não a ordem dos argumentos. Enquanto a ordem decidia,
  /// esta chamada trazia a remoção ocorrida durante a queda e a descartava.
  Future<void> _reloadRecent() async {
    try {
      _applyServer(
        await _repository.fetchHistory(
          groupId: space.groupId,
          actionId: space.actionId,
        ),
      );
    } catch (_) {
      // A conversa continua com o que já tinha. O canal está de pé de novo.
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

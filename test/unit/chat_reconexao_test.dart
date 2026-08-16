import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/chat_state.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat_canal_helper.dart';

/// Change `chat-de-grupo-e-acao` — o cenário "Conexão cai e volta".
///
/// `mergeMessages` já está provado em unidade (`chat_deducao_test.dart`) e a
/// entrega pelo canal em integração (`chat_realtime_test.dart`). O que nenhum
/// dos dois toca é a EMENDA: a transição `reconnecting → subscribed` em
/// `chat_providers.dart`, que refaz a consulta. Ela é o único ponto do sistema
/// onde as duas fontes se cruzam de verdade, e é onde as duas metades da spec
/// nascem juntas — a mensagem da queda aparece, e a que o canal já tinha
/// entregue não aparece duas vezes.
///
/// O segundo caso é da convergência 5, e ele estava escondido atrás do
/// primeiro: **este arquivo comparava só `id`s**, nunca conteúdo. A remoção
/// ocorrida durante a queda voltava da consulta e era descartada pela cópia
/// velha, e o texto removido continuava desenhado — com a lista de `id`s
/// perfeitamente correta.

class MockChatRepository extends Mock implements ChatRepository {}

const _space = ChatSpace.group('g1');

Message _message(String id, {required int minute}) => Message(
  id: id,
  authorId: 'autor-1',
  createdAt: DateTime.utc(2026, 8, 14, 10, minute),
  groupId: 'g1',
  text: 'mensagem $id',
  authorName: 'Ana',
);

void main() {
  setUpAll(registerChatFallbacks);

  /// Liga o provider aos dublês e devolve o que o teste precisa manipular.
  ({FakeRealtime realtime, List<ChatState> states}) start(
    MockChatRepository repository,
  ) {
    final realtime = FakeRealtime();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(realtime.client),
        chatRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final states = <ChatState>[];
    container.listen(chatProvider(_space), (_, next) {
      final state = next.value;
      if (state != null) states.add(state);
    }, fireImmediately: true);

    return (realtime: realtime, states: states);
  }

  test(
    'reconexão traz o que chegou na queda e não duplica o que o canal entregou',
    () async {
      final repository = MockChatRepository();

      // `m1` já estava lá quando a tela abriu. `m2` é a mensagem dita DURANTE a
      // queda — só a segunda consulta a conhece. `m3` o canal entregou ao vivo,
      // e a segunda consulta a devolve de novo: é a candidata a duplicata.
      final first = _message('m1', minute: 0);
      final duringOutage = _message('m2', minute: 1);
      final fromChannel = _message('m3', minute: 2);

      var historyCalls = 0;
      when(
        () => repository.fetchHistory(
          groupId: any(named: 'groupId'),
          actionId: any(named: 'actionId'),
        ),
      ).thenAnswer((_) async {
        historyCalls++;
        // A consulta pede as mais recentes primeiro — é assim que o repositório
        // de verdade responde, e a ordenação final é do `merge`.
        return historyCalls == 1 ? [first] : [fromChannel, duringOutage, first];
      });
      when(
        () => repository.withAuthorName(any()),
      ).thenAnswer((_) async => fromChannel);

      final run = start(repository);
      await settleMicrotasks();
      expect(
        run.states.last.messages.map((m) => m.id),
        ['m1'],
        reason: 'a tela abre com o histórico da primeira consulta',
      );

      run.realtime.setStatus(RealtimeSubscribeStatus.subscribed);
      await settleMicrotasks();
      expect(run.states.last.connection, ChatConnection.live);
      expect(
        historyCalls,
        1,
        reason:
            'a PRIMEIRA assinatura não pode reconsultar — seria uma ida ao '
            'servidor a mais em toda abertura de conversa',
      );

      // Ao vivo, alguém fala. Chega só pelo canal.
      run.realtime.deliver(
        PostgresChangePayload(
          schema: 'public',
          table: 'mensagens',
          commitTimestamp: fromChannel.createdAt,
          eventType: PostgresChangeEvent.insert,
          newRecord: {
            'id': 'm3',
            'autor_id': 'autor-1',
            'created_at': fromChannel.createdAt.toIso8601String(),
            'grupo_id': 'g1',
            'texto': 'mensagem m3',
          },
          oldRecord: const {},
          errors: null,
        ),
      );
      await settleMicrotasks();
      expect(run.states.last.messages.map((m) => m.id), ['m1', 'm3']);

      // A queda. O canal para de entregar e ninguém avisa o que passou.
      run.realtime.setStatus(RealtimeSubscribeStatus.closed);
      await settleMicrotasks();
      expect(
        run.states.last.connection,
        ChatConnection.reconnecting,
        reason: 'a tela precisa DIZER que não está ao vivo',
      );

      // A volta.
      run.realtime.setStatus(RealtimeSubscribeStatus.subscribed);
      await settleMicrotasks();

      expect(
        historyCalls,
        2,
        reason: 'voltar do `reconnecting` tem de refazer a consulta',
      );
      expect(
        run.states.last.messages.map((m) => m.id),
        ['m1', 'm2', 'm3'],
        reason:
            'm2 é o que passou na queda; m3 veio pelos dois caminhos e aparece '
            'uma vez só',
      );
      expect(run.states.last.connection, ChatConnection.live);
    },
  );

  test('a remoção ocorrida DURANTE a queda sobrevive à reconexão', () async {
    // Convergência 5. Medido antes do conserto: `consultas=2`,
    // `texto_na_tela='o texto que a moderação tirou'`, `removida_em=null`,
    // `lapide=visible`. A consulta da reconexão trouxe a linha removida, e a
    // cópia de antes da queda ganhou dela — porque quem vencia era "quem chega
    // depois", e nesse caminho quem chega depois é a versão VELHA.
    //
    // A regra agora é a lápide absorvente (ver `mergeMessages`), e ela não
    // depende de ordem de chegada: texto não ressuscita, então a versão com
    // menos texto é sempre a mais nova.
    final repository = MockChatRepository();
    final withText = _message('m1', minute: 0);
    final removed = Message(
      id: 'm1',
      authorId: 'autor-1',
      createdAt: withText.createdAt,
      groupId: 'g1',
      removedAt: DateTime.utc(2026, 8, 14, 10, 5),
      authorName: 'Ana',
    );

    var historyCalls = 0;
    when(
      () => repository.fetchHistory(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer((_) async {
      historyCalls++;
      return historyCalls == 1 ? [withText] : [removed];
    });

    final run = start(repository);
    await settleMicrotasks();
    run.realtime.setStatus(RealtimeSubscribeStatus.subscribed);
    await settleMicrotasks();
    expect(run.states.last.messages.single.text, 'mensagem m1');

    // A queda — e é durante ela que a moderação remove.
    run.realtime.setStatus(RealtimeSubscribeStatus.closed);
    await settleMicrotasks();
    run.realtime.setStatus(RealtimeSubscribeStatus.subscribed);
    await settleMicrotasks();

    expect(historyCalls, 2);
    final message = run.states.last.messages.single;
    expect(
      message.text,
      isNull,
      reason:
          'a spec de moderação diz que o texto removido não volta para '
          'ninguém, e a reconexão é justamente o caminho que existe para '
          'contar o que passou',
    );
    expect(message.tombstone, MessageTombstone.removedByModeration);
  });
}

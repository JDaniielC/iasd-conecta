import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat_canal_helper.dart';

class MockChatRepository extends Mock implements ChatRepository {}

/// Change `mensagem-fixada`, convergência 1 — a volta do canal refaz a
/// consulta das FIXADAS, não só a do histórico.
///
/// O buraco que este arquivo fecha: entre a queda e a volta, o canal não
/// entrega nada e ninguém avisa o que passou. O histórico refeito traz a
/// fixação das linhas que estão na PÁGINA — mas a fixada antiga, fora dela,
/// que é o caso que motivou `fetchPinned` existir, só vem pela consulta
/// própria. Sem ela, fixar ou desfixar durante a queda não aparecia na faixa
/// até a pessoa fechar e reabrir a tela, e ela não tem como saber que precisa.
///
/// O contraste está no último caso: consulta que FALHA não pode esvaziar a
/// faixa. Falha e "não há fixada nenhuma" são coisas diferentes, e tratá-las
/// igual seria trocar um defeito por outro pior.

const _space = ChatSpace.group('g1');

Message _pinned(String id, String text) => Message(
  id: id,
  authorId: 'u1',
  createdAt: DateTime.utc(2026, 1, 1),
  groupId: 'g1',
  text: text,
  pinnedAt: DateTime.utc(2026, 8, 14, 20),
  pinnedBy: 'dono-1',
  authorName: 'Fulana',
);

Message _plain(String id, String text) => Message(
  id: id,
  authorId: 'u1',
  createdAt: DateTime.utc(2026, 8, 14, 19),
  groupId: 'g1',
  text: text,
  authorName: 'Fulana',
);

Future<FakeRealtime> _pumpChat(
  WidgetTester tester,
  MockChatRepository repository,
) async {
  final fake = FakeRealtime();
  final router = GoRouter(
    initialLocation: '/grupos/g1/conversa',
    routes: [
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, state) =>
            const ChatPage(space: _space, title: 'SevenBikers'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        supabaseClientProvider.overrideWithValue(fake.client),
        chatRepositoryProvider.overrideWithValue(repository),
        canModerateSpaceProvider(_space).overrideWith((ref) async => false),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUpAll(registerChatFallbacks);

  void stubHistory(MockChatRepository repository, List<Message> rows) {
    when(
      () => repository.fetchHistory(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
        before: any(named: 'before'),
      ),
    ).thenAnswer((_) async => rows);
  }

  testWidgets('a fixada ANTIGA fixada durante a queda aparece na volta', (
    tester,
  ) async {
    final repository = MockChatRepository();
    // A conversa da página NÃO contém a fixada — é o caso que dá sentido ao
    // teste: pelo histórico ela nunca chegaria.
    stubHistory(repository, [_plain('m1', 'a conversa de hoje')]);

    var round = 0;
    when(
      () => repository.fetchPinned(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer(
      (_) async => round++ == 0
          ? const <Message>[]
          : [_pinned('antiga', 'o endereço, combinado lá atrás')],
    );

    final fake = await _pumpChat(tester, repository);
    expect(find.textContaining('fixada'), findsNothing);

    // Cai e volta. A primeira assinatura não reconsulta — é a abertura.
    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    fake.setStatus(RealtimeSubscribeStatus.closed);
    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    await tester.pumpAndSettle();

    expect(find.text('1 mensagem fixada'), findsOneWidget);
  });

  testWidgets('a fixada DESFIXADA durante a queda some da faixa na volta', (
    tester,
  ) async {
    final repository = MockChatRepository();
    stubHistory(repository, [_plain('m1', 'a conversa de hoje')]);

    var round = 0;
    when(
      () => repository.fetchPinned(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer(
      (_) async => round++ == 0
          ? [_pinned('antiga', 'o endereço, combinado lá atrás')]
          : const <Message>[],
    );

    final fake = await _pumpChat(tester, repository);
    expect(find.text('1 mensagem fixada'), findsOneWidget);

    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    fake.setStatus(RealtimeSubscribeStatus.closed);
    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    await tester.pumpAndSettle();

    // `_rememberPinned` sozinho só sabe ENTRAR — ele trata uma linha por vez,
    // e a linha desfixada nunca chega por evento nenhum quando o canal esteve
    // caído. Por isso a volta REFAZ a faixa em vez de acrescentar a ela.
    expect(find.textContaining('fixada'), findsNothing);
  });

  testWidgets('desfixar mensagem ANTIGA não a injeta na conversa', (
    tester,
  ) async {
    // Convergência 3, medido: `mergeMessages` ACRESCENTA id desconhecido, e o
    // canal filtra por espaço e não por tempo. Sem a guarda, o `update` de uma
    // fixada de três meses atrás entrava na conversa de quem nunca paginou até
    // lá — e virava o cursor de `loadOlder`, jogando todo o histórico
    // intermediário para fora de alcance.
    final repository = MockChatRepository();
    stubHistory(repository, [_plain('m1', 'a conversa de hoje')]);
    when(
      () => repository.fetchPinned(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer(
      (_) async => [_pinned('antiga', 'o endereço, combinado lá atrás')],
    );
    when(() => repository.withAuthorName(any())).thenAnswer(
      (invocation) async => Message.fromMap(
        invocation.positionalArguments.first as Map<String, dynamic>,
        authorName: 'Fulana',
      ),
    );

    final fake = await _pumpChat(tester, repository);
    expect(find.text('1 mensagem fixada'), findsOneWidget);
    expect(find.text('a conversa de hoje'), findsOneWidget);

    // O servidor desfixa a antiga. `fixada_em` volta nulo na linha inteira.
    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    fake.deliver(
      PostgresChangePayload(
        schema: 'public',
        table: 'mensagens',
        commitTimestamp: DateTime.utc(2026, 8, 14, 21),
        eventType: PostgresChangeEvent.update,
        newRecord: {
          'id': 'antiga',
          'autor_id': 'u1',
          'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
          'grupo_id': 'g1',
          'texto': 'o endereço, combinado lá atrás',
          'removida_em': null,
          'fixada_em': null,
          'fixada_por': null,
        },
        oldRecord: const {},
        errors: null,
      ),
    );
    await tester.pumpAndSettle();

    // A faixa esvaziou — é o efeito que o evento DEVE ter.
    expect(find.textContaining('fixada'), findsNothing);

    // E a conversa NÃO ganhou a mensagem de janeiro. Sem a guarda, ela apareceria
    // aqui e passaria a ser a mais antiga da lista, que é o cursor da paginação.
    expect(
      find.text('o endereço, combinado lá atrás'),
      findsNothing,
      reason: 'a linha antiga entrou na conversa de quem não paginou até lá',
    );
    expect(find.text('a conversa de hoje'), findsOneWidget);
  });

  testWidgets('mensagem NOVA pelo canal continua entrando na conversa', (
    tester,
  ) async {
    // O contraste, e ele é o que impede a guarda de virar um filtro que engole
    // o caso normal: `insert` de linha que a tela não conhece é justamente a
    // mensagem que acabou de nascer.
    final repository = MockChatRepository();
    stubHistory(repository, [_plain('m1', 'a conversa de hoje')]);
    when(
      () => repository.fetchPinned(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer((_) async => const <Message>[]);
    when(() => repository.withAuthorName(any())).thenAnswer(
      (invocation) async => Message.fromMap(
        invocation.positionalArguments.first as Map<String, dynamic>,
        authorName: 'Fulana',
      ),
    );

    final fake = await _pumpChat(tester, repository);

    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    fake.deliver(
      PostgresChangePayload(
        schema: 'public',
        table: 'mensagens',
        commitTimestamp: DateTime.utc(2026, 8, 14, 21),
        eventType: PostgresChangeEvent.insert,
        newRecord: {
          'id': 'nova',
          'autor_id': 'u2',
          'created_at': DateTime.utc(2026, 8, 14, 21).toIso8601String(),
          'grupo_id': 'g1',
          'texto': 'acabei de falar',
          'removida_em': null,
          'fixada_em': null,
          'fixada_por': null,
        },
        oldRecord: const {},
        errors: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('acabei de falar'), findsOneWidget);
  });

  testWidgets('consulta que FALHA na volta não esvazia a faixa', (
    tester,
  ) async {
    final repository = MockChatRepository();
    stubHistory(repository, [_plain('m1', 'a conversa de hoje')]);

    var round = 0;
    when(
      () => repository.fetchPinned(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer((_) async {
      if (round++ == 0) {
        return [_pinned('antiga', 'o endereço, combinado lá atrás')];
      }
      throw Exception('rede caiu de novo');
    });

    final fake = await _pumpChat(tester, repository);
    expect(find.text('1 mensagem fixada'), findsOneWidget);

    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    fake.setStatus(RealtimeSubscribeStatus.closed);
    fake.setStatus(RealtimeSubscribeStatus.subscribed);
    await tester.pumpAndSettle();

    // Falha e "não há fixada nenhuma" são fatos diferentes. Tratar os dois
    // igual apagaria a faixa por causa de uma consulta que não voltou.
    expect(
      find.text('1 mensagem fixada'),
      findsOneWidget,
      reason: 'a faixa sumiu por causa de uma consulta que falhou',
    );
  });
}

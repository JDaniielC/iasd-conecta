import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat_canal_helper.dart';

/// Change `chat-de-grupo-e-acao` — a tela não depende do canal para desenhar o
/// que a própria pessoa fez, e o servidor sempre vence a cópia local.
///
/// **O canal está morto em todos os casos deste arquivo**, e é o cenário
/// inteiro: enquanto ele estiver de pé, o eco do próprio `insert` desenha a
/// mensagem e o teste passaria sem provar nada. `FakeRealtime` sem
/// `setStatus(subscribed)` é exatamente isso — assinatura aberta que nunca
/// sobe, que é como o cliente do Supabase se comporta durante uma queda.
///
/// A decisão está no design, em "Quem manda na lista da conversa": a consulta é
/// a fonte, o canal é otimização, e a lista desenhada é
/// `servidor ∪ o que eu acabei de escrever`.
///
/// Os testes usam o `ChatNotifier` DE VERDADE, com o repositório em dublê. Um
/// stub do provider provaria só que a tela desenha o que lhe entregam — e o que
/// falhou nas convergências 3, 4 e 5 foi sempre a composição da lista, não o
/// desenho.

class MockChatRepository extends Mock implements ChatRepository {}

const _space = ChatSpace.group('g1');

Message _message(String id, {int minute = 0, String? text}) => Message(
  id: id,
  authorId: 'u1',
  createdAt: DateTime.utc(2026, 8, 14, 10, minute),
  groupId: 'g1',
  text: text ?? 'mensagem $id',
  authorName: 'Fulana',
);

/// Um stub só para as DUAS consultas, decidindo por `before`.
///
/// Dois `when` separados não funcionam: o `any(named: 'before')` do mocktail
/// casa também com a chamada que OMITE o parâmetro, e o último registro vence —
/// a consulta de abertura passava a devolver a página anterior, e o teste de
/// paginação já abria com ela na tela.
void _stubHistory(
  MockChatRepository repository, {
  required List<Message> initial,
  List<Message> older = const [],
}) {
  when(
    () => repository.fetchHistory(
      groupId: any(named: 'groupId'),
      actionId: any(named: 'actionId'),
      before: any(named: 'before'),
    ),
  ).thenAnswer(
    (invocation) async =>
        invocation.namedArguments[#before] == null ? initial : older,
  );
  // A consulta das fixadas roda JUNTO com a de abertura desde
  // `mensagem-fixada`. Sem este stub ela cai no caminho de falha e devolve
  // vazio — que é o resultado certo por acidente, e acidente não é prova.
  when(
    () => repository.fetchPinned(
      groupId: any(named: 'groupId'),
      actionId: any(named: 'actionId'),
    ),
  ).thenAnswer((_) async => const <Message>[]);
}

Future<FakeRealtime> _pumpChat(
  WidgetTester tester,
  MockChatRepository repository,
) async {
  final fake = FakeRealtime();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(fake.client),
        chatRepositoryProvider.overrideWithValue(repository),
        canModerateSpaceProvider(_space).overrideWith((ref) async => false),
        currentUserIdProvider.overrideWithValue('u1'),
      ],
      child: const MaterialApp(
        home: ChatPage(space: _space, title: 'Grupo'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUpAll(registerChatFallbacks);

  testWidgets('enviar com o canal CAÍDO mostra a mensagem assim mesmo', (
    tester,
  ) async {
    final repository = MockChatRepository();
    _stubHistory(repository, initial: [_message('a')]);
    when(
      () => repository.send(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((_) async => _message('nova', minute: 5, text: 'às 19h'));

    await _pumpChat(tester, repository);

    await tester.enterText(find.byType(TextField), 'às 19h');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(
      find.text('às 19h'),
      findsOneWidget,
      reason:
          'a pessoa escreveu, o campo limpou — a frase precisa estar na tela, '
          'não sumir esperando um canal que está caído',
    );
  });

  testWidgets('REMOVER com o canal caído tira o texto da tela na hora', (
    tester,
  ) async {
    // Convergência 5. Medido antes do conserto: o `update` acontecia no banco,
    // `texto_ainda_na_tela=true` e `lapide_na_tela=false` — a tela de quem
    // mandou remover continuava com o texto, sem erro e sem lápide, porque o
    // único caminho que redesenhava era o evento do canal. A spec de moderação
    // diz que o texto removido não volta para ninguém, e quem remove é alguém.
    final repository = MockChatRepository();
    _stubHistory(
      repository,
      initial: [_message('m1', text: 'o que eu não devia ter escrito')],
    );
    when(() => repository.removeMessage(any())).thenAnswer((_) async {});

    await _pumpChat(tester, repository);

    await tester.tap(find.text('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    verify(() => repository.removeMessage('m1')).called(1);
    expect(find.text('o que eu não devia ter escrito'), findsNothing);
    expect(find.text('Mensagem removida.'), findsOneWidget);
  });

  testWidgets('remover o que acabei de escrever mantém a lápide NO LUGAR', (
    tester,
  ) async {
    // Convergência 6, e o defeito nasceu do conserto anterior: `_pending` foi
    // criada para a mensagem própria aparecer com o canal caído, e `remove`
    // procurava a versão atual só em `_server`. Medido antes: `autor=""`,
    // `nome=null`, `created=2026-08-16` numa conversa de 14/08 — a lápide ia
    // para o fim da conversa, assinada por "Alguém".
    //
    // A spec pede que "as mensagens seguintes continuem na mesma ordem", e a
    // marca existe para dizer que houve algo ALI.
    final repository = MockChatRepository();
    _stubHistory(
      repository,
      initial: [_message('velha', text: 'a primeira da conversa')],
    );
    when(
      () => repository.send(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((_) async => _message('minha', minute: 1, text: 'ops, errei'));
    when(() => repository.removeMessage(any())).thenAnswer((_) async {});

    await _pumpChat(tester, repository);

    await tester.enterText(find.byType(TextField), 'ops, errei');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // A lista é `reverse: true`: o primeiro "Remover" da árvore é o da mensagem
    // mais nova, que é a que acabou de ser enviada e ainda só existe local.
    await tester.tap(find.text('Remover').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    verify(() => repository.removeMessage('minha')).called(1);

    final state = ProviderScope.containerOf(
      tester.element(find.byType(ChatPage)),
    ).read(chatProvider(_space)).value!;
    final tombstone = state.messages.firstWhere((m) => m.id == 'minha');

    expect(state.messages.map((m) => m.id), [
      'velha',
      'minha',
    ], reason: 'ordem');
    expect(tombstone.createdAt, DateTime.utc(2026, 8, 14, 10, 1));
    expect(tombstone.authorId, 'u1');
    expect(tombstone.authorName, 'Fulana');
    expect(tombstone.text, isNull);
  });

  testWidgets('carregar o que veio antes acrescenta as mensagens anteriores', (
    tester,
  ) async {
    final repository = MockChatRepository();
    _stubHistory(
      repository,
      initial: [_message('b', minute: 9)],
      older: [_message('antiga', text: 'lá de trás')],
    );

    await _pumpChat(tester, repository);
    expect(find.text('lá de trás'), findsNothing);

    await tester.tap(find.text('Carregar o que veio antes'));
    await tester.pumpAndSettle();

    expect(find.text('lá de trás'), findsOneWidget);
  });

  testWidgets('página vazia tira o botão — não adianta pedir de novo', (
    tester,
  ) async {
    final repository = MockChatRepository();
    _stubHistory(repository, initial: [_message('b')]);

    await _pumpChat(tester, repository);

    await tester.tap(find.text('Carregar o que veio antes'));
    await tester.pumpAndSettle();

    expect(find.text('Carregar o que veio antes'), findsNothing);
  });

  testWidgets('a REMOÇÃO vinda do servidor apaga a cópia local do remetente', (
    tester,
  ) async {
    // Convergência 4. `_justSent` foi criada para a mensagem própria aparecer
    // com o canal caído, e entrava como o argumento VENCEDOR de
    // `mergeMessages` — com isso a cópia local ganhava até da remoção, e quem
    // escreveu continuava com o texto na tela depois de ele ser removido.
    final repository = MockChatRepository();
    _stubHistory(repository, initial: [_message('a')]);
    final sent = _message('nova', minute: 5, text: 'às 19h');
    when(
      () => repository.send(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
        text: any(named: 'text'),
      ),
    ).thenAnswer((_) async => sent);
    when(() => repository.withAuthorName(any())).thenAnswer(
      (_) async => Message(
        id: 'nova',
        authorId: 'u1',
        createdAt: sent.createdAt,
        groupId: 'g1',
        removedAt: DateTime.utc(2026, 8, 14, 11),
        authorName: 'Fulana',
      ),
    );

    final fake = await _pumpChat(tester, repository);

    await tester.enterText(find.byType(TextField), 'às 19h');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(find.text('às 19h'), findsOneWidget, reason: 'apareceu ao enviar');

    // Agora o servidor fala da MESMA linha, dizendo que ela foi removida.
    fake.deliver(
      PostgresChangePayload(
        schema: 'public',
        table: 'mensagens',
        commitTimestamp: DateTime.utc(2026, 8, 14, 11),
        eventType: PostgresChangeEvent.update,
        newRecord: {
          'id': 'nova',
          'autor_id': 'u1',
          'created_at': sent.createdAt.toIso8601String(),
          'grupo_id': 'g1',
          'texto': null,
          'removida_em': DateTime.utc(2026, 8, 14, 11).toIso8601String(),
        },
        oldRecord: const {},
        errors: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('às 19h'), findsNothing);
    expect(find.text('Mensagem removida.'), findsOneWidget);
  });

  testWidgets(
    'o EXPURGO alcança a página anterior, não só o que estava à vista',
    (tester) async {
      // Convergência 5. As páginas anteriores moravam no estado do widget, e o
      // callback de `delete` só filtrava a lista do provider. Medido antes do
      // conserto: `antiga_na_tela=true`, `recente_na_tela=false` — sumia só o que
      // o provider conhecia, e a mensagem expurgada continuava legível. A
      // Política promete que ela deixa de existir depois de 30 dias.
      final repository = MockChatRepository();
      _stubHistory(
        repository,
        initial: [_message('recente', minute: 9)],
        older: [_message('antiga', text: 'lá de trás')],
      );

      final fake = await _pumpChat(tester, repository);
      await tester.tap(find.text('Carregar o que veio antes'));
      await tester.pumpAndSettle();
      expect(find.text('lá de trás'), findsOneWidget);

      // O expurgo apaga a linha. `delete` chega com `newRecord` vazio.
      fake.deliver(
        PostgresChangePayload(
          schema: 'public',
          table: 'mensagens',
          commitTimestamp: DateTime.utc(2026, 8, 14, 12),
          eventType: PostgresChangeEvent.delete,
          newRecord: const {},
          oldRecord: const {'id': 'antiga'},
          errors: null,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('lá de trás'),
        findsNothing,
        reason:
            'some do banco, tem de sumir daqui — inclusive da página anterior',
      );
      expect(find.text('mensagem recente'), findsOneWidget);
    },
  );
}

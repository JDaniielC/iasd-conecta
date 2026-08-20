import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/features/action/data/voting_round_repository.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';
import 'package:iasd_conecta/features/action/presentation/create_voting_round_page.dart';
import 'package:iasd_conecta/features/action/voting_round_providers.dart';
import 'package:mocktail/mocktail.dart';

/// `CreateVotingRoundPage` — abertura de Rodada. Estava em 0/44 linhas até a
/// change `cobertura-e-tdd`. Julgada na largura de celular (360).

class MockVotingRoundRepository extends Mock implements VotingRoundRepository {}

class _FakeNewVotingRound extends Fake implements NewVotingRound {}

const _groupId = 'g1';

Widget _app(VotingRoundRepository repository) {
  final router = GoRouter(
    initialLocation: '/grupos/$_groupId/rodadas/novo',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('tela anterior')),
      GoRoute(
        path: '/grupos/$_groupId/rodadas/novo',
        builder: (_, _) => const CreateVotingRoundPage(groupId: _groupId),
      ),
    ],
  );

  return ProviderScope(
    overrides: [votingRoundRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(WidgetTester tester, VotingRoundRepository repository) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_app(repository));
  await tester.pumpAndSettle();
}

/// Escolhe um prazo pelos seletores nativos. `showDatePicker` abre no dia
/// seguinte e `showTimePicker` na hora atual — confirmar os dois sem mexer já
/// produz um prazo no futuro, que é o caso feliz.
Future<void> _pickFutureDeadline(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Escolher prazo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  // O seletor de hora abre no modo relógio; o botão OK confirma a hora atual.
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeNewVotingRound()));

  testWidgets('a tela explica o que se está escolhendo', (tester) async {
    await _pump(tester, MockVotingRoundRepository());

    expect(find.text('Escolha até quando a votação fica aberta.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Escolher prazo'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Abrir Rodada'), findsOneWidget);
  });

  testWidgets('abrir sem escolher prazo recusa e diz o que falta', (tester) async {
    final repository = MockVotingRoundRepository();
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir Rodada'));
    await tester.pumpAndSettle();

    expect(find.text('Escolha um prazo.'), findsOneWidget);
    // Nada foi enviado ao banco sobre um formulário incompleto.
    verifyNever(() => repository.openRound(any(), groupId: any(named: 'groupId')));
  });

  testWidgets('prazo escolhido aparece no botão, formatado', (tester) async {
    await _pump(tester, MockVotingRoundRepository());
    await _pickFutureDeadline(tester);

    expect(find.widgetWithText(OutlinedButton, 'Escolher prazo'), findsNothing);
    // O rótulo vira a data escolhida em dd/MM/yyyy HH:mm.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^\d{2}/\d{2}/\d{4} \d{2}:\d{2}$').hasMatch(w.data!),
      ),
      findsOneWidget,
    );
  });

  testWidgets('com prazo no futuro, abre a Rodada e volta para a tela anterior',
      (tester) async {
    final repository = MockVotingRoundRepository();
    when(() => repository.openRound(any(), groupId: any(named: 'groupId')))
        .thenAnswer((_) async => 'r-nova');

    await _pump(tester, repository);
    await _pickFutureDeadline(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir Rodada'));
    await tester.pumpAndSettle();

    verify(() => repository.openRound(any(), groupId: _groupId)).called(1);
  });

  testWidgets('escrita recusada avisa e não apresenta a Rodada como aberta',
      (tester) async {
    final repository = MockVotingRoundRepository();
    when(() => repository.openRound(any(), groupId: any(named: 'groupId')))
        .thenThrow(StateError('não participa do Grupo'));

    await _pump(tester, repository);
    await _pickFutureDeadline(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir Rodada'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não deu pra abrir a Rodada agora. Você participa deste Grupo?'),
      findsOneWidget,
    );
    // A tela continua no formulário, com o botão de novo disponível.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Abrir Rodada'),
    );
    expect(button.onPressed, isNotNull);
  });
}

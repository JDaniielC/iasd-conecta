import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/leadership/data/leadership_repository.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';
import 'package:iasd_conecta/features/leadership/leadership_providers.dart';
import 'package:iasd_conecta/features/leadership/presentation/declare_leadership_page.dart';
import 'package:iasd_conecta/features/profile/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

/// `DeclareLeadershipPage` — FR-002: autodeclarar exige **Conta**, não só
/// Perfil. Estava em 0/40 linhas até a change `cobertura-e-tdd`.
/// Julgada na largura de celular (360).

class MockLeadershipRepository extends Mock implements LeadershipRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

const _groupId = 'g1';

LeadershipDeclaration _declaration({
  DateTime? confirmedAt,
  DateTime? rejectedAt,
}) =>
    LeadershipDeclaration(
      id: 'd1',
      groupId: _groupId,
      userId: 'quem-declara',
      year: 2026,
      declaredAt: DateTime(2026, 2, 1),
      confirmedAt: confirmedAt,
      rejectedAt: rejectedAt,
    );

Widget _app({
  LeadershipDeclaration? declaration,
  bool hasAccount = true,
  LeadershipRepository? repository,
  Object? declarationError,
}) {
  final auth = MockAuthRepository();
  when(() => auth.hasAccount).thenReturn(hasAccount);

  final router = GoRouter(
    initialLocation: '/grupos/$_groupId/lideranca',
    routes: [
      GoRoute(
        path: '/grupos/$_groupId/lideranca',
        builder: (_, _) => const DeclareLeadershipPage(groupId: _groupId),
      ),
      GoRoute(path: '/upgrade-conta', builder: (_, _) => const Text('tela de criar Conta')),
    ],
  );

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      leadershipRepositoryProvider
          .overrideWithValue(repository ?? MockLeadershipRepository()),
      myDeclarationProvider(_groupId).overrideWith(
        (ref) async => declarationError != null ? throw declarationError : declaration,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tela diz que o Administrador confirma antes de valer', (tester) async {
    await _pump(tester, _app());

    expect(
      find.textContaining('O Administrador do distrito confirma antes de valer.'),
      findsOneWidget,
    );
  });

  group('O estado da minha declaração', () {
    testWidgets('sem declaração, diz que ainda não houve', (tester) async {
      await _pump(tester, _app());

      expect(find.text('Você ainda não se autodeclarou esse ano.'), findsOneWidget);
    });

    testWidgets('pendente diz pendente', (tester) async {
      await _pump(tester, _app(declaration: _declaration()));

      expect(find.text('Sua declaração está pendente de confirmação.'), findsOneWidget);
    });

    testWidgets('confirmada diz confirmada', (tester) async {
      await _pump(tester, _app(declaration: _declaration(confirmedAt: DateTime(2026, 3, 1))));

      expect(find.text('Sua declaração já foi confirmada.'), findsOneWidget);
    });

    testWidgets('rejeitada diz que declarar de novo reabre a análise', (tester) async {
      await _pump(tester, _app(declaration: _declaration(rejectedAt: DateTime(2026, 3, 1))));

      expect(
        find.text('Sua declaração foi rejeitada. Autodeclarar de novo reabre a análise.'),
        findsOneWidget,
      );
      // E o botão continua disponível — é o que a frase promete.
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Autodeclarar'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('declaração que não carrega avisa em vez de dizer que não existe',
        (tester) async {
      await _pump(tester, _app(declarationError: StateError('falha de rede')));

      expect(find.text('Não deu pra carregar sua declaração.'), findsOneWidget);
      expect(find.text('Você ainda não se autodeclarou esse ano.'), findsNothing);
    });
  });

  group('FR-002: exige Conta, não só Perfil', () {
    testWidgets('sem Conta, o toque leva ao upgrade e nada é declarado', (tester) async {
      final repository = MockLeadershipRepository();
      await _pump(tester, _app(hasAccount: false, repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Autodeclarar'));
      await tester.pumpAndSettle();

      expect(find.text('tela de criar Conta'), findsOneWidget);
      verifyNever(() => repository.declare(
            groupId: any(named: 'groupId'),
            year: any(named: 'year'),
          ));
    });

    testWidgets('com Conta, declara', (tester) async {
      final repository = MockLeadershipRepository();
      when(() => repository.declare(
            groupId: any(named: 'groupId'),
            year: any(named: 'year'),
          )).thenAnswer((_) async {});

      await _pump(tester, _app(repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Autodeclarar'));
      await tester.pumpAndSettle();

      verify(() => repository.declare(
            groupId: _groupId,
            year: DateTime.now().year,
          )).called(1);
      expect(find.text('tela de criar Conta'), findsNothing);
    });
  });

  testWidgets('escrita recusada avisa e não apresenta a declaração como feita',
      (tester) async {
    final repository = MockLeadershipRepository();
    when(() => repository.declare(
          groupId: any(named: 'groupId'),
          year: any(named: 'year'),
        )).thenThrow(StateError('recusado'));

    await _pump(tester, _app(repository: repository));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Autodeclarar'));
    await tester.pumpAndSettle();

    expect(find.text('Não deu pra autodeclarar. Tente de novo.'), findsOneWidget);
    expect(find.text('Você ainda não se autodeclarou esse ano.'), findsOneWidget);
  });
}

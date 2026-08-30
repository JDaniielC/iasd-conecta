import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';
import 'package:iasd_conecta/features/action/presentation/voting_round_list_page.dart';
import 'package:iasd_conecta/features/action/voting_round_providers.dart';
import 'package:iasd_conecta/features/notification/notification_providers.dart';

/// `VotingRoundListPage` — FR-017: a lista é visível a Visitante e a Usuário
/// igualmente; o que o Visitante não faz é abrir Rodada. Estava em 0/24 linhas
/// até a change `cobertura-e-tdd`. Julgada na largura de celular (360).

const _groupId = 'g1';

VotingRound _round(String id, {DateTime? closedAt}) => VotingRound(
      id: id,
      groupId: _groupId,
      openedBy: 'dona',
      deadline: DateTime(2027, 5, 20, 21),
      closedAt: closedAt,
    );

Widget _app({
  required List<VotingRound> rounds,
  bool hasProfile = true,
  Object? error,
}) {
  final router = GoRouter(
    initialLocation: '/grupos/$_groupId/rodadas',
    routes: [
      GoRoute(
        path: '/grupos/$_groupId/rodadas',
        builder: (_, _) => const VotingRoundListPage(groupId: _groupId),
      ),
      GoRoute(path: '/cadastro', builder: (_, _) => const Text('tela de cadastro')),
      GoRoute(path: '/notificacoes', builder: (_, _) => const Text('tela de avisos')),
      GoRoute(
        path: '/grupos/$_groupId/rodadas/novo',
        builder: (_, _) => const Text('tela de abrir Rodada'),
      ),
      GoRoute(path: '/rodadas/:id', builder: (_, _) => const Text('tela da Rodada')),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('alguem'),
      // `async`, como o provider real. Foi síncrono enquanto `ProfileGuard`
      // lia `.value ?? false` — aí um override assíncrono não tinha efeito e o
      // guard recusava todo mundo. Desde a change `afirmar-sem-conferir` o
      // guard espera a resposta, e o override volta a ser o normal.
      hasProfileProvider.overrideWith((ref) async => hasProfile),
      unreadNotificationCountProvider.overrideWith((ref) async => 0),
      groupVotingRoundsProvider(_groupId).overrideWith(
        (ref) async => error != null ? throw error : rounds,
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
  testWidgets('lista Rodadas com estado e prazo formatado', (tester) async {
    await _pump(
      tester,
      _app(rounds: [_round('r1'), _round('r2', closedAt: DateTime(2027, 5, 21))]),
    );

    expect(find.text('Aberta'), findsOneWidget);
    expect(find.text('Fechada'), findsOneWidget);
    expect(find.text('Prazo: 20/05/2027 21:00'), findsNWidgets(2));
  });

  testWidgets('sem Rodada nenhuma, diz isso em vez de tela em branco', (tester) async {
    await _pump(tester, _app(rounds: const []));

    expect(find.text('Nenhuma Rodada ainda.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('tocar numa Rodada abre a Rodada', (tester) async {
    await _pump(tester, _app(rounds: [_round('r1')]));

    await tester.tap(find.text('Aberta'));
    await tester.pumpAndSettle();

    expect(find.text('tela da Rodada'), findsOneWidget);
  });

  testWidgets('falha de carregamento avisa em vez de mostrar lista vazia',
      (tester) async {
    await _pump(tester, _app(rounds: const [], error: StateError('falha de rede')));

    expect(find.text('Não deu pra carregar as Rodadas agora.'), findsOneWidget);
    // Não pode dizer "nenhuma Rodada" quando o que houve foi falha.
    expect(find.text('Nenhuma Rodada ainda.'), findsNothing);
  });

  group('FR-017: a lista é de todo mundo, abrir Rodada não é', () {
    testWidgets('Visitante vê a lista igual', (tester) async {
      await _pump(tester, _app(rounds: [_round('r1')], hasProfile: false));

      expect(find.text('Aberta'), findsOneWidget);
      expect(find.text('Prazo: 20/05/2027 21:00'), findsOneWidget);
    });

    testWidgets('Visitante que tenta abrir Rodada para no cadastro', (tester) async {
      await _pump(tester, _app(rounds: const [], hasProfile: false));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('tela de cadastro'), findsOneWidget);
      expect(find.text('tela de abrir Rodada'), findsNothing);
    });

    testWidgets('quem tem Perfil chega na tela de abrir Rodada', (tester) async {
      await _pump(tester, _app(rounds: const []));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('tela de abrir Rodada'), findsOneWidget);
    });
  });
}

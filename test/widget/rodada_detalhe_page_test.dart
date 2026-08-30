import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/data/voting_round_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';
import 'package:iasd_conecta/features/action/presentation/voting_round_detail_page.dart';
import 'package:iasd_conecta/features/action/voting_round_providers.dart';
import 'package:iasd_conecta/features/notification/notification_providers.dart';
import 'package:mocktail/mocktail.dart';

/// `VotingRoundDetailPage` — a tela onde a pessoa vota e onde a Rodada é
/// encerrada. Estava em 0/66 linhas cobertas até a change `cobertura-e-tdd`,
/// e é regra que o Princípio IV chama de inegociável (revogabilidade de voto,
/// descarte ao fechar).
///
/// Julgada na largura de celular (360), nunca na de desktop.

class MockVotingRoundRepository extends Mock implements VotingRoundRepository {}

const _roundId = 'r1';

VotingRound _round({DateTime? closedAt}) => VotingRound(
      id: _roundId,
      groupId: 'g1',
      openedBy: 'dona',
      deadline: DateTime(2027, 3, 10, 19, 30),
      closedAt: closedAt,
    );

Action _candidate(String id, String name) => Action(
      id: id,
      name: name,
      dateTime: DateTime(2027, 3, 15, 8),
      location: 'Praça Central',
      creatorId: 'quem-propos',
      createdAt: DateTime(2027, 3, 1),
      votingRoundId: _roundId,
      isConfirmed: false,
    );

/// A tela navega com `context.push`, então precisa de um GoRouter de verdade —
/// as rotas de destino existem só para o push não estourar.
Widget _app({
  required VotingRound round,
  required List<Action> candidates,
  Vote? myVote,
  bool hasProfile = true,
  VotingRoundRepository? repository,
  Object? roundError,
  Object? candidatesError,
}) {
  final router = GoRouter(
    initialLocation: '/rodadas/$_roundId',
    routes: [
      GoRoute(
        path: '/rodadas/$_roundId',
        builder: (_, _) => const VotingRoundDetailPage(votingRoundId: _roundId),
      ),
      GoRoute(path: '/cadastro', builder: (_, _) => const Text('tela de cadastro')),
      GoRoute(path: '/notificacoes', builder: (_, _) => const Text('tela de avisos')),
      GoRoute(
        path: '/rodadas/$_roundId/candidatas/novo',
        builder: (_, _) => const Text('tela de propor candidata'),
      ),
      GoRoute(path: '/acoes/:id', builder: (_, _) => const Text('tela de detalhe da Ação')),
    ],
  );

  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('quem-vota'),
      // `async`, como o provider real. Foi síncrono enquanto `ProfileGuard`
      // lia `.value ?? false` — um FutureProvider nunca lido nasce
      // AsyncLoading, e o override assíncrono não tinha efeito nenhum. Desde a
      // change `afirmar-sem-conferir` o guard espera a resposta.
      hasProfileProvider.overrideWith((ref) async => hasProfile),
      unreadNotificationCountProvider.overrideWith((ref) async => 0),
      votingRoundProvider(_roundId).overrideWith(
        (ref) async => roundError != null ? throw roundError : round,
      ),
      candidatesProvider(_roundId).overrideWith(
        (ref) async => candidatesError != null ? throw candidatesError : candidates,
      ),
      myVoteProvider(_roundId).overrideWith((ref) async => myVote),
      if (repository != null)
        votingRoundRepositoryProvider.overrideWithValue(repository),
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
  group('Rodada aberta', () {
    testWidgets('mostra Aberta, o prazo formatado e as candidatas', (tester) async {
      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar'), _candidate('c2', 'Culto na Praça')],
        ),
      );

      expect(find.text('Aberta'), findsOneWidget);
      expect(find.text('Prazo: 10/03/2027 19:30'), findsOneWidget);
      expect(find.text('Visita ao Lar'), findsOneWidget);
      expect(find.text('Culto na Praça'), findsOneWidget);
    });

    testWidgets('oferece Votar em cada candidata, e Propor e Encerrar', (tester) async {
      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar'), _candidate('c2', 'Culto na Praça')],
        ),
      );

      expect(find.widgetWithText(OutlinedButton, 'Votar'), findsNWidgets(2));
      expect(find.widgetWithText(ElevatedButton, 'Propor Candidata'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Encerrar Rodada'), findsOneWidget);
    });

    testWidgets('sem candidata nenhuma, diz isso em vez de lista vazia', (tester) async {
      await _pump(tester, _app(round: _round(), candidates: const []));

      expect(find.text('Nenhuma candidata ainda.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Votar'), findsNothing);
    });
  });

  group('O voto que já é meu', () {
    testWidgets('a candidata em que votei diz "Seu voto" e o botão fica desabilitado',
        (tester) async {
      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar'), _candidate('c2', 'Culto na Praça')],
          myVote: const Vote(userId: 'quem-vota', candidateId: 'c1'),
        ),
      );

      expect(find.text('Seu voto'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Seu voto'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a outra candidata continua votável — o voto é revogável', (tester) async {
      final repository = MockVotingRoundRepository();
      when(() => repository.vote(any(), any())).thenAnswer((_) async {});

      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar'), _candidate('c2', 'Culto na Praça')],
          myVote: const Vote(userId: 'quem-vota', candidateId: 'c1'),
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Votar'));
      await tester.pumpAndSettle();

      verify(() => repository.vote(_roundId, 'c2')).called(1);
    });
  });

  group('Rodada fechada', () {
    testWidgets('diz Fechada e não oferece Votar, Propor nem Encerrar', (tester) async {
      await _pump(
        tester,
        _app(
          round: _round(closedAt: DateTime(2027, 3, 11)),
          candidates: [_candidate('c1', 'Visita ao Lar')],
        ),
      );

      expect(find.text('Fechada'), findsOneWidget);
      expect(find.text('Aberta'), findsNothing);
      // A candidata continua listada — só o que se pode fazer com ela some.
      expect(find.text('Visita ao Lar'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Votar'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Propor Candidata'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Encerrar Rodada'), findsNothing);
    });
  });

  group('Caminhos de falha', () {
    testWidgets('votar numa Rodada que já fechou avisa, e a tela não mente', (tester) async {
      final repository = MockVotingRoundRepository();
      when(() => repository.vote(any(), any())).thenThrow(StateError('rodada fechada'));

      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar')],
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Votar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não deu pra votar agora. A Rodada ainda está aberta?'),
        findsOneWidget,
      );
      // O botão continua oferecendo Votar — nada foi apresentado como feito.
      expect(find.widgetWithText(OutlinedButton, 'Votar'), findsOneWidget);
    });

    testWidgets('encerrar que falha avisa em vez de dizer que encerrou', (tester) async {
      final repository = MockVotingRoundRepository();
      when(() => repository.closeIfDue(any(), force: any(named: 'force')))
          .thenThrow(StateError('sem autoridade'));

      await _pump(
        tester,
        _app(round: _round(), candidates: const [], repository: repository),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Encerrar Rodada'));
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra encerrar agora. Tente de novo.'), findsOneWidget);
      expect(find.text('Aberta'), findsOneWidget);
    });

    testWidgets('Rodada que não carrega diz isso', (tester) async {
      await _pump(
        tester,
        _app(round: _round(), candidates: const [], roundError: StateError('sumiu')),
      );

      expect(find.text('Rodada não encontrada.'), findsOneWidget);
    });

    testWidgets('candidatas que não carregam não derrubam o resto da tela',
        (tester) async {
      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: const [],
          candidatesError: StateError('falha de rede'),
        ),
      );

      expect(find.text('Não deu pra carregar as candidatas.'), findsOneWidget);
      // A Rodada em si continua legível.
      expect(find.text('Aberta'), findsOneWidget);
    });
  });

  group('Visitante sem Perfil', () {
    testWidgets('votar sem Perfil manda para o cadastro em vez de votar', (tester) async {
      final repository = MockVotingRoundRepository();
      when(() => repository.vote(any(), any())).thenAnswer((_) async {});

      await _pump(
        tester,
        _app(
          round: _round(),
          candidates: [_candidate('c1', 'Visita ao Lar')],
          hasProfile: false,
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Votar'));
      await tester.pumpAndSettle();

      expect(find.text('tela de cadastro'), findsOneWidget);
      verifyNever(() => repository.vote(any(), any()));
    });

    testWidgets('propor candidata sem Perfil também para no cadastro', (tester) async {
      await _pump(
        tester,
        _app(round: _round(), candidates: const [], hasProfile: false),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Propor Candidata'));
      await tester.pumpAndSettle();

      expect(find.text('tela de cadastro'), findsOneWidget);
      expect(find.text('tela de propor candidata'), findsNothing);
    });
  });
}

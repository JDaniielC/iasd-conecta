import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/action/data/action_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_detail_page.dart';
import 'package:mocktail/mocktail.dart';

class MockAcaoRepository extends Mock implements ActionRepository {}

final _acao = Action(
  id: 'a1',
  name: 'Acampamento',
  dateTime: DateTime(2027, 3, 10, 8, 0),
  local: 'Sítio',
  creatorId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'FR-011: confirmar presença sem Perfil direciona pro cadastro',
    (tester) async {
      final acaoRepo = MockAcaoRepository();
      when(() => acaoRepo.fetchAction('a1')).thenAnswer((_) async => _acao);
      when(() => acaoRepo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      final router = GoRouter(
        initialLocation: '/acoes/a1',
        routes: [
          GoRoute(
            path: '/acoes/:id',
            builder: (context, state) => ActionDetailPage(actionId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/cadastro', builder: (context, state) => const Text('TELA_CADASTRO')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            actionRepositoryProvider.overrideWithValue(acaoRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar presença'), findsOneWidget);

      await tester.tap(find.text('Confirmar presença'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => acaoRepo.confirmAttendance(any()));
    },
  );

  group('Ação encerrada (US1)', () {
    final agora = DateTime(2026, 8, 9, 12, 0);

    Future<void> pumpDetalhe(WidgetTester tester, Action action) async {
      final repo = MockAcaoRepository();
      when(() => repo.fetchAction('a1')).thenAnswer((_) async => action);
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => true),
            currentUserIdProvider.overrideWithValue(null),
            isDistrictAdminProvider.overrideWith((ref) async => false),
            actionRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => agora),
          ],
          child: MaterialApp(
            home: const ActionDetailPage(actionId: 'a1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Action acaoEm(DateTime quando, {DateTime? cancelledAt}) => Action(
          id: 'a1',
          name: 'Visita a afastado',
          dateTime: quando,
          local: 'alto jose leal',
          creatorId: 'dono-1',
          createdAt: DateTime(2026, 1, 1),
          cancelledAt: cancelledAt,
        );

    testWidgets('abre por link direto e mostra o rótulo de encerrada (FR-004)',
        (tester) async {
      await pumpDetalhe(
        tester,
        acaoEm(agora.subtract(const Duration(hours: 5))),
      );

      expect(find.text('Visita a afastado'), findsOneWidget);
      expect(find.text('Encerrada'), findsOneWidget);
    });

    testWidgets('não oferece confirmar, desistir nem cancelar (FR-005)',
        (tester) async {
      await pumpDetalhe(
        tester,
        acaoEm(agora.subtract(const Duration(hours: 5))),
      );

      expect(find.text('Confirmar presença'), findsNothing);
      expect(find.text('Desistir'), findsNothing);
      expect(find.text('Sair da fila de espera'), findsNothing);
      expect(find.byTooltip('Cancelar Ação'), findsNothing);
    });

    testWidgets('Ação ainda acontecendo continua aceitando confirmar (FR-002)',
        (tester) async {
      await pumpDetalhe(
        tester,
        acaoEm(agora.subtract(const Duration(hours: 1))),
      );

      expect(find.text('Encerrada'), findsNothing);
      expect(find.text('Confirmar presença'), findsOneWidget);
    });

    testWidgets('cancelada e encerrada: o rótulo é "Cancelada" (FR-008)',
        (tester) async {
      await pumpDetalhe(
        tester,
        acaoEm(
          agora.subtract(const Duration(hours: 5)),
          cancelledAt: agora.subtract(const Duration(days: 1)),
        ),
      );

      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Encerrada'), findsNothing);
    });
  });
}

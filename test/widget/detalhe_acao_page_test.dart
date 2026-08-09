import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
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

  group('numeração dos confirmados (US4)', () {
    final agora = DateTime(2026, 8, 9, 12, 0);

    Future<void> pumpCom(
      WidgetTester tester,
      List<AttendanceWithProfile> attendees,
    ) async {
      final repo = MockAcaoRepository();
      when(() => repo.fetchAction('a1')).thenAnswer(
        (_) async => Action(
          id: 'a1',
          name: 'Culto Jovem',
          dateTime: agora.add(const Duration(days: 1)),
          local: 'Templo',
          creatorId: 'dono-1',
          createdAt: DateTime(2026, 1, 1),
          capacity: 3,
        ),
      );
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => attendees);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => true),
            currentUserIdProvider.overrideWithValue(null),
            isDistrictAdminProvider.overrideWith((ref) async => false),
            actionRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => agora),
          ],
          child: const MaterialApp(home: ActionDetailPage(actionId: 'a1')),
        ),
      );
      await tester.pumpAndSettle();
    }

    AttendanceWithProfile pessoa(String nome, AttendanceStatus status) =>
        AttendanceWithProfile(
          profile: PublicProfile(id: nome, displayName: nome),
          status: status,
        );

    testWidgets('confirmados aparecem numerados 1., 2., 3. (FR-020)',
        (tester) async {
      await pumpCom(tester, [
        pessoa('Ana', AttendanceStatus.confirmed),
        pessoa('Bruno', AttendanceStatus.confirmed),
        pessoa('Kesia', AttendanceStatus.confirmed),
      ]);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Kesia'), findsOneWidget);
    });

    testWidgets('a fila tem numeração própria, recomeçando em 1. (FR-021)',
        (tester) async {
      await pumpCom(tester, [
        pessoa('Ana', AttendanceStatus.confirmed),
        pessoa('Bruno', AttendanceStatus.waitlist),
        pessoa('Kesia', AttendanceStatus.waitlist),
      ]);

      // 1. aparece duas vezes: uma nos confirmados, outra na fila.
      expect(find.text('1.'), findsNWidgets(2));
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('Fila de espera'), findsOneWidget);
    });

    testWidgets('numeração fica contígua depois de uma desistência (FR-022)',
        (tester) async {
      // Estado depois de a segunda pessoa desistir: quem sobra é renumerado
      // pelo índice, então não há buraco.
      await pumpCom(tester, [
        pessoa('Ana', AttendanceStatus.confirmed),
        pessoa('Kesia', AttendanceStatus.confirmed),
      ]);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsNothing);
    });

    testWidgets('sem ninguém confirmado, mostra mensagem de vazio (FR-023)',
        (tester) async {
      await pumpCom(tester, const []);

      expect(find.text('Ninguém confirmou presença ainda.'), findsOneWidget);
      expect(find.text('1.'), findsNothing);
    });
  });
}

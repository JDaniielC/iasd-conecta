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

class MockActionRepository extends Mock implements ActionRepository {}

final _action = Action(
  id: 'a1',
  name: 'Acampamento',
  dateTime: DateTime(2027, 3, 10, 8, 0),
  location: 'Sítio',
  creatorId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'FR-011: confirmar presença sem Perfil direciona pro cadastro',
    (tester) async {
      final actionRepo = MockActionRepository();
      when(() => actionRepo.fetchAction('a1')).thenAnswer((_) async => _action);
      when(() => actionRepo.fetchAttendees('a1')).thenAnswer((_) async => const []);

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
            actionRepositoryProvider.overrideWithValue(actionRepo),
            isAnonymousProvider.overrideWithValue(false),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar presença'), findsOneWidget);

      await tester.tap(find.text('Confirmar presença'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => actionRepo.confirmAttendance(any()));
    },
  );

  group('Ação encerrada (US1)', () {
    final now = DateTime(2026, 8, 9, 12, 0);

    Future<void> pumpDetail(WidgetTester tester, Action action) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1')).thenAnswer((_) async => action);
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => true),
            currentUserIdProvider.overrideWithValue(null),
            isDistrictAdminProvider.overrideWith((ref) async => false),
            // Change `convite-para-acao`: a tela pergunta se o Perfil é
            // anônimo para decidir entre "Convidar" e o caminho de Conta.
            isAnonymousProvider.overrideWithValue(false),
            actionRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(
            home: const ActionDetailPage(actionId: 'a1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Action actionAt(DateTime quando, {DateTime? cancelledAt}) => Action(
          id: 'a1',
          name: 'Visita a afastado',
          dateTime: quando,
          location: 'alto jose leal',
          creatorId: 'dono-1',
          createdAt: DateTime(2026, 1, 1),
          cancelledAt: cancelledAt,
        );

    testWidgets('abre por link direto e mostra o rótulo de encerrada (FR-004)',
        (tester) async {
      await pumpDetail(
        tester,
        actionAt(now.subtract(const Duration(hours: 5))),
      );

      expect(find.text('Visita a afastado'), findsOneWidget);
      expect(find.text('Encerrada'), findsOneWidget);
    });

    testWidgets('não oferece confirmar, desistir nem cancelar (FR-005)',
        (tester) async {
      await pumpDetail(
        tester,
        actionAt(now.subtract(const Duration(hours: 5))),
      );

      expect(find.text('Confirmar presença'), findsNothing);
      expect(find.text('Desistir'), findsNothing);
      expect(find.text('Sair da fila de espera'), findsNothing);
      expect(find.byTooltip('Cancelar Ação'), findsNothing);
    });

    testWidgets('Ação ainda acontecendo continua aceitando confirmar (FR-002)',
        (tester) async {
      await pumpDetail(
        tester,
        actionAt(now.subtract(const Duration(hours: 1))),
      );

      expect(find.text('Encerrada'), findsNothing);
      expect(find.text('Confirmar presença'), findsOneWidget);
    });

    testWidgets('cancelada e encerrada: o rótulo é "Cancelada" (FR-008)',
        (tester) async {
      await pumpDetail(
        tester,
        actionAt(
          now.subtract(const Duration(hours: 5)),
          cancelledAt: now.subtract(const Duration(days: 1)),
        ),
      );

      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Encerrada'), findsNothing);
    });
  });

  group('numeração dos confirmados (US4)', () {
    final now = DateTime(2026, 8, 9, 12, 0);

    Future<void> pumpWith(
      WidgetTester tester,
      List<AttendanceWithProfile> attendees,
    ) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1')).thenAnswer(
        (_) async => Action(
          id: 'a1',
          name: 'Culto Jovem',
          dateTime: now.add(const Duration(days: 1)),
          location: 'Templo',
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
            // Change `convite-para-acao`: a tela pergunta se o Perfil é
            // anônimo para decidir entre "Convidar" e o caminho de Conta.
            isAnonymousProvider.overrideWithValue(false),
            actionRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => now),
          ],
          child: const MaterialApp(home: ActionDetailPage(actionId: 'a1')),
        ),
      );
      await tester.pumpAndSettle();
    }

    AttendanceWithProfile person(String name, AttendanceStatus status) =>
        AttendanceWithProfile(
          profile: PublicProfile(id: name, displayName: name),
          status: status,
        );

    testWidgets('confirmados aparecem numerados 1., 2., 3. (FR-020)',
        (tester) async {
      await pumpWith(tester, [
        person('Ana', AttendanceStatus.confirmed),
        person('Bruno', AttendanceStatus.confirmed),
        person('Kesia', AttendanceStatus.confirmed),
      ]);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Kesia'), findsOneWidget);
    });

    testWidgets('a fila tem numeração própria, recomeçando em 1. (FR-021)',
        (tester) async {
      await pumpWith(tester, [
        person('Ana', AttendanceStatus.confirmed),
        person('Bruno', AttendanceStatus.waitlist),
        person('Kesia', AttendanceStatus.waitlist),
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
      await pumpWith(tester, [
        person('Ana', AttendanceStatus.confirmed),
        person('Kesia', AttendanceStatus.confirmed),
      ]);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsNothing);
    });

    testWidgets('sem ninguém confirmado, mostra mensagem de vazio (FR-023)',
        (tester) async {
      await pumpWith(tester, const []);

      expect(find.text('Ninguém confirmou presença ainda.'), findsOneWidget);
      expect(find.text('1.'), findsNothing);
    });
  });
}

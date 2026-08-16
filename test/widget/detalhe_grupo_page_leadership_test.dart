import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/group_detail_page.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';
import 'package:iasd_conecta/features/leadership/leadership_providers.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

final _group = Group(
  id: 'g1',
  name: 'Ministério de Louvor',
  category: 'Ministério',
  schedule: 'sábados 9h',
  location: 'Templo',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

LeadershipDeclaration _confirmed(String id, String userId) {
  return LeadershipDeclaration(
    id: id,
    groupId: 'g1',
    userId: userId,
    year: DateTime.now().year,
    declaredAt: DateTime(2026, 1, 1),
    confirmedAt: DateTime(2026, 1, 2),
    confirmedBy: 'admin-1',
  );
}

void main() {
  testWidgets(
    'FR-006/FR-007: exibe todos os Líderes confirmados do ano corrente (codireção)',
    (tester) async {
      final groupRepo = MockGroupRepository();
      when(() => groupRepo.fetchGroup('g1')).thenAnswer((_) async => _group);
      when(() => groupRepo.fetchMembers('g1')).thenAnswer(
        (_) async => const [PublicProfile(id: 'dono-1', displayName: 'Dono')],
      );

      final router = GoRouter(
        initialLocation: '/grupos/g1',
        routes: [
          GoRoute(
            path: '/grupos/:id',
            builder: (context, state) => GroupDetailPage(groupId: state.pathParameters['id']!),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            groupRepositoryProvider.overrideWithValue(groupRepo),
            currentLeadersProvider('g1').overrideWith(
              (ref) async => [_confirmed('l1', 'lider-1'), _confirmed('l2', 'lider-2')],
            ),
            publicProfileProvider('lider-1').overrideWith(
              (ref) async => const PublicProfile(id: 'lider-1', displayName: 'Ana Líder'),
            ),
            publicProfileProvider('lider-2').overrideWith(
              (ref) async => const PublicProfile(id: 'lider-2', displayName: 'Beto Diretor'),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Líder/Diretor'), findsOneWidget);
      expect(find.text('Ana Líder'), findsOneWidget);
      expect(find.text('Beto Diretor'), findsOneWidget);
    },
  );

  testWidgets(
    'sem Líder confirmado, a seção não aparece',
    (tester) async {
      final groupRepo = MockGroupRepository();
      when(() => groupRepo.fetchGroup('g1')).thenAnswer((_) async => _group);
      when(() => groupRepo.fetchMembers('g1')).thenAnswer(
        (_) async => const [PublicProfile(id: 'dono-1', displayName: 'Dono')],
      );

      final router = GoRouter(
        initialLocation: '/grupos/g1',
        routes: [
          GoRoute(
            path: '/grupos/:id',
            builder: (context, state) => GroupDetailPage(groupId: state.pathParameters['id']!),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            groupRepositoryProvider.overrideWithValue(groupRepo),
            currentLeadersProvider('g1').overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Líder/Diretor'), findsNothing);
    },
  );
}

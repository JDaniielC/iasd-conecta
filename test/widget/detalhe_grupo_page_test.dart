import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/group_detail_page.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

final _group = Group(
  id: 'g1',
  name: 'SevenBikers',
  category: 'Ministério Jovem',
  schedule: 'sábados 6h',
  location: 'Praça Central',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'FR-008/FR-009: Participar sem Perfil direciona pro cadastro',
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
          GoRoute(path: '/cadastro', builder: (context, state) => const Text('TELA_CADASTRO')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            groupRepositoryProvider.overrideWithValue(groupRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Participar'), findsOneWidget);

      await tester.tap(find.text('Participar'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => groupRepo.join(any()));
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/group_list_page.dart';
import 'package:iasd_conecta/features/profile/data/auth_repository.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

final _group = Group(
  id: 'g1',
  name: 'SevenBikers',
  category: 'Ministério Jovem',
  schedule: 'Sábados, 19h',
  location: 'Praça Central',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

Future<MockGroupRepository> _pump(
  WidgetTester tester, {
  required String currentUserId,
  List<PublicProfile> members = const [
    PublicProfile(id: 'dono-1', displayName: 'Dono'),
  ],
}) async {
  final groupRepo = MockGroupRepository();
  when(() => groupRepo.fetchGroups()).thenAnswer((_) async => [_group]);
  when(() => groupRepo.fetchMembers('g1')).thenAnswer((_) async => members);
  when(() => groupRepo.join('g1')).thenAnswer((_) async {});
  when(() => groupRepo.leave('g1')).thenAnswer((_) async {});
  final authRepo = MockAuthRepository();
  when(() => authRepo.hasAccount).thenReturn(true);

  final router = GoRouter(
    initialLocation: '/grupos',
    routes: [
      GoRoute(
        path: '/grupos',
        builder: (context, state) => const GroupListPage(),
      ),
      GoRoute(
        path: '/grupos/:id',
        builder: (context, state) =>
            Text('TELA_DETALHE_${state.pathParameters['id']}'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        currentUserIdProvider.overrideWithValue(currentUserId),
        groupRepositoryProvider.overrideWithValue(groupRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
        churchesProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('SevenBikers'));
  await tester.pumpAndSettle();

  return groupRepo;
}

void main() {
  testWidgets('tocar o cartão abre a pré-visualização, não a tela cheia direto',
      (tester) async {
    await _pump(tester, currentUserId: 'menor-1');

    // A pré-visualização mostra o essencial, sem sair de /grupos — a
    // categoria aparece duas vezes de propósito (cartão da lista por baixo +
    // chip da prévia), o resto só uma.
    expect(find.text('Ministério Jovem'), findsWidgets);
    expect(find.textContaining('Sábados, 19h'), findsOneWidget);
    expect(find.textContaining('Praça Central'), findsOneWidget);
    expect(find.text('TELA_DETALHE_g1'), findsNothing);
  });

  testWidgets('"Ver detalhes" fecha a prévia e navega pra tela cheia',
      (tester) async {
    await _pump(tester, currentUserId: 'menor-1');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Ver detalhes'));
    await tester.pumpAndSettle();

    expect(find.text('TELA_DETALHE_g1'), findsOneWidget);
  });

  testWidgets('quem não participa vê "Participar", e tocar chama join',
      (tester) async {
    final repo = await _pump(tester, currentUserId: 'visitante-1');

    expect(find.widgetWithText(OutlinedButton, 'Participar'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Participar'));
    await tester.pumpAndSettle();

    verify(() => repo.join('g1')).called(1);
  });

  testWidgets('quem já participa vê "Sair", e tocar chama leave', (tester) async {
    final repo = await _pump(
      tester,
      currentUserId: 'dono-1',
      members: const [
        PublicProfile(id: 'dono-1', displayName: 'Dono'),
        PublicProfile(id: 'membro-2', displayName: 'Bia'),
      ],
    );

    expect(find.widgetWithText(OutlinedButton, 'Sair'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sair'));
    await tester.pumpAndSettle();

    verify(() => repo.leave('g1')).called(1);
  });
}

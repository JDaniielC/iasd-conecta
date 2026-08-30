import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/my_groups_page.dart';

final _groups = [
  Group(
    id: 'g1',
    name: 'SevenBikers',
    category: 'Ministério Jovem',
    ownerId: 'dono-1',
    createdAt: DateTime(2026, 1, 1),
  ),
  Group(
    id: 'g2',
    name: 'Coral',
    category: 'Ministério da Música',
    ownerId: 'dono-2',
    createdAt: DateTime(2026, 1, 2),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required Set<String> myGroupIds,
}) async {
  final router = GoRouter(
    initialLocation: '/meus-grupos',
    routes: [
      GoRoute(
        path: '/meus-grupos',
        builder: (context, state) => const MyGroupsPage(),
      ),
      GoRoute(
        path: '/grupos',
        builder: (context, state) => const Text('TELA_GRUPOS'),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Text('TELA_HOME'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => myGroupIds.isNotEmpty),
        myGroupIdsProvider.overrideWith((ref) async => myGroupIds),
        groupsProvider.overrideWith((ref) async => _groups),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('só mostra os Grupos em que a pessoa participa', (tester) async {
    await _pump(tester, myGroupIds: {'g1'});

    expect(find.text('SevenBikers'), findsOneWidget);
    expect(find.text('Coral'), findsNothing);
  });

  testWidgets('sem nenhum Grupo, convida a conhecer os Grupos', (tester) async {
    await _pump(tester, myGroupIds: {});

    expect(find.text('Você ainda não participa de nenhum Grupo.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver Grupos/Ministérios'));
    await tester.pumpAndSettle();

    expect(find.text('TELA_GRUPOS'), findsOneWidget);
  });

  testWidgets('tem caminho de volta pra Home', (tester) async {
    await _pump(tester, myGroupIds: {'g1'});

    await tester.tap(find.byTooltip('Início'));
    await tester.pumpAndSettle();

    expect(find.text('TELA_HOME'), findsOneWidget);
  });
}

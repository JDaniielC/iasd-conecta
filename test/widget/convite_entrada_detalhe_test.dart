import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/data/action_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_detail_page.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:mocktail/mocktail.dart';

/// Change `convite-para-acao` — a entrada de "Convidar" no detalhe da Ação.
///
/// A regra de verdade está em `convidar_para_acao`, que lê
/// `auth.users.is_anonymous`. A tela não é a garantia: ela apenas não oferece o
/// que o banco recusaria, e no lugar mostra o caminho de virar Conta. Oferecer
/// o botão e deixar a pessoa descobrir no erro seria pior que não oferecer.

class MockActionRepository extends Mock implements ActionRepository {}

Action _acao({DateTime? cancelledAt, DateTime? dateTime}) => Action(
      id: 'a1',
      name: 'Encontro',
      dateTime: dateTime ?? DateTime(2027, 3, 10, 8),
      location: 'Sede',
      creatorId: 'criador-1',
      createdAt: DateTime(2026, 1, 1),
      cancelledAt: cancelledAt,
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool anonimo,
  Action? acao,
}) async {
  final repo = MockActionRepository();
  when(() => repo.fetchAction('a1')).thenAnswer((_) async => acao ?? _acao());
  when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

  final router = GoRouter(
    initialLocation: '/acoes/a1',
    routes: [
      GoRoute(
        path: '/acoes/:id',
        builder: (context, state) =>
            ActionDetailPage(actionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/acoes/:id/convidar',
        builder: (context, state) => const Text('TELA_CONVIDAR'),
      ),
      GoRoute(
        path: '/upgrade-conta',
        builder: (context, state) => const Text('TELA_UPGRADE'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        currentUserIdProvider.overrideWithValue('quem-abre'),
        isAnonymousProvider.overrideWithValue(anonimo),
        isDistrictAdminProvider.overrideWith((ref) async => false),
        actionRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quem tem Conta vê "Convidar" e chega na tela', (tester) async {
    await _pump(tester, anonimo: false);
    expect(find.text('Convidar'), findsOneWidget);
    expect(find.text('Criar Conta para convidar'), findsNothing);

    await tester.tap(find.text('Convidar'));
    await tester.pumpAndSettle();
    expect(find.text('TELA_CONVIDAR'), findsOneWidget);
  });

  testWidgets('Perfil anônimo vê o caminho de Conta no lugar de "Convidar"',
      (tester) async {
    await _pump(tester, anonimo: true);
    expect(find.text('Convidar'), findsNothing);
    expect(find.text('Criar Conta para convidar'), findsOneWidget);

    await tester.tap(find.text('Criar Conta para convidar'));
    await tester.pumpAndSettle();
    expect(find.text('TELA_UPGRADE'), findsOneWidget);
  });

  testWidgets('Ação cancelada não oferece convidar a ninguém', (tester) async {
    await _pump(tester, anonimo: false, acao: _acao(cancelledAt: DateTime(2026, 8, 1)));
    expect(find.text('Convidar'), findsNothing);
    expect(find.text('Criar Conta para convidar'), findsNothing);
  });
}

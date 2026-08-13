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

/// Change `acao-direcionada-a-grupo` — o que a tela mostra, e o que ela NÃO
/// mostra.
///
/// O caso do link direto é o que importa mais: quem não participa do Grupo tem
/// de cair em "Ação não encontrada" sem nome, data nem local. Não é uma tela
/// nova — `fetchAction` usa `.single()`, e com a Ação escondida pela policy a
/// resposta vem sem linha, o que joga o `AsyncValue` para `error`. Este teste
/// existe para essa cadeia continuar valendo: alguém trocando `.single()` por
/// `.maybeSingle()` acharia que está sendo gentil e passaria a renderizar uma
/// tela de Ação vazia no lugar do "não encontrada".

class MockActionRepository extends Mock implements ActionRepository {}

Action _action({bool restricted = false, String? groupId = 'g1'}) => Action(
      id: 'a1',
      name: 'Reunião de liderança',
      dateTime: DateTime(2027, 3, 10, 8, 0),
      local: 'Sala 2',
      creatorId: 'criador-1',
      createdAt: DateTime(2026, 1, 1),
      groupId: groupId,
      restrictedToGroup: restricted,
    );

Widget _app(MockActionRepository repo, {String? uid}) {
  final router = GoRouter(
    initialLocation: '/acoes/a1',
    routes: [
      GoRoute(
        path: '/acoes/:id',
        builder: (context, state) =>
            ActionDetailPage(actionId: state.pathParameters['id']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      hasProfileProvider.overrideWith((ref) async => uid != null),
      currentUserIdProvider.overrideWithValue(uid),
      actionRepositoryProvider.overrideWithValue(repo),
      isDistrictAdminProvider.overrideWith((ref) async => false),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    'link direto para Ação restrita sem acesso cai em "Ação não encontrada", '
    'sem revelar nome, data nem local',
    (tester) async {
      final repo = MockActionRepository();
      // É assim que o banco responde: a linha não existe para quem lê.
      when(() => repo.fetchAction('a1')).thenThrow(Exception('sem linha'));
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(_app(repo, uid: 'de-fora'));
      await tester.pumpAndSettle();

      expect(find.text('Ação não encontrada.'), findsOneWidget);
      expect(find.text('Reunião de liderança'), findsNothing);
      expect(find.textContaining('Sala 2'), findsNothing);
      expect(find.textContaining('10/03/2027'), findsNothing);
    },
  );

  testWidgets(
    'quem vê a Ação restrita mas não pode mudá-la lê a marca, sem controle',
    (tester) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1'))
          .thenAnswer((_) async => _action(restricted: true));
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(_app(repo, uid: 'participante-comum'));
      await tester.pumpAndSettle();

      expect(find.text('Só para quem participa do Grupo'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );

  testWidgets(
    'quem criou a Ação de Grupo ganha o controle, e o texto não sai duplicado',
    (tester) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1'))
          .thenAnswer((_) async => _action(restricted: true));
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(_app(repo, uid: 'criador-1'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('Só para quem participa do Grupo'), findsOneWidget);
    },
  );

  testWidgets(
    'quando a escrita não pega, a tela avisa em vez de deixar o interruptor '
    'voltar calado',
    (tester) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1'))
          .thenAnswer((_) async => _action(restricted: false));
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);
      // É assim que uma recusa por RLS de `update` chega: nenhuma linha
      // afetada, nenhum erro do servidor.
      when(() => repo.setRestrictedToGroup('a1', true))
          .thenThrow(StateError('nada mudou'));

      await tester.pumpWidget(_app(repo, uid: 'criador-1'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Não deu pra mudar quem vê esta Ação'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Ação avulsa não oferece o controle de restrição a ninguém',
    (tester) async {
      final repo = MockActionRepository();
      when(() => repo.fetchAction('a1'))
          .thenAnswer((_) async => _action(groupId: null));
      when(() => repo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      await tester.pumpWidget(_app(repo, uid: 'criador-1'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNothing);
    },
  );
}

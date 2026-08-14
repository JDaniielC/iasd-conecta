import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/features/invite/data/invite_repository.dart';
import 'package:iasd_conecta/features/invite/domain/action_invite.dart';
import 'package:iasd_conecta/features/invite/domain/invite_contact.dart';
import 'package:iasd_conecta/features/invite/domain/invite_contact_group.dart';
import 'package:iasd_conecta/features/invite/invite_providers.dart';
import 'package:iasd_conecta/features/invite/presentation/invite_to_action_page.dart';
import 'package:mocktail/mocktail.dart';

/// Change `convite-para-acao` — a tela de convidar, julgada em 360 px.
///
/// O caso que mais importa é a falha parcial. A spec proíbe afirmar sucesso
/// quando a chamada falhou, e exige dizer NOMINALMENTE quem ficou de fora — um
/// "2 de 3 enviados" não deixa a pessoa saber quem ela ainda precisa chamar.

class MockInviteRepository extends Mock implements InviteRepository {}

const _actionId = 'a1';

final _grupos = [
  InviteContactGroup(
    groupId: 'g1',
    groupName: 'Jovens',
    contacts: const [
      InviteContact(
          userId: 'u1',
          displayName: 'Ana',
          alreadyInvited: false,
          alreadyConfirmed: false),
      InviteContact(
          userId: 'u2',
          displayName: 'Bruno',
          alreadyInvited: false,
          alreadyConfirmed: false),
      InviteContact(
          userId: 'u3',
          displayName: 'Carla',
          alreadyInvited: true,
          alreadyConfirmed: false),
      // Convidada e já respondeu — é a segunda metade do acompanhamento.
      InviteContact(
          userId: 'u4',
          displayName: 'Dora',
          alreadyInvited: true,
          alreadyConfirmed: true),
    ],
  ),
];

Future<void> _pump(
  WidgetTester tester,
  MockInviteRepository repo, {
  List<InviteContactGroup>? contatos,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/acoes/$_actionId/convidar',
    routes: [
      GoRoute(
        path: '/acoes/:id/convidar',
        builder: (context, state) =>
            InviteToActionPage(actionId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/grupos', builder: (context, state) => const Text('TELA_GRUPOS')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inviteRepositoryProvider.overrideWithValue(repo),
        inviteContactsProvider(_actionId)
            .overrideWith((ref) async => contatos ?? _grupos),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem Grupo nenhum, a tela explica de onde vem a lista e leva '
      'aos Grupos', (tester) async {
    final repo = MockInviteRepository();
    await _pump(tester, repo, contatos: const []);

    expect(
      find.textContaining('vem dos seus Grupos'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ver Grupos'));
    await tester.pumpAndSettle();
    expect(find.text('TELA_GRUPOS'), findsOneWidget);
  });

  testWidgets('quem já foi convidado aparece marcado e não selecionável',
      (tester) async {
    final repo = MockInviteRepository();
    await _pump(tester, repo);

    final carla = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Carla'),
    );
    expect(carla.value, isTrue);
    expect(carla.onChanged, isNull);
    expect(find.text('Já convidado — sem resposta'), findsOneWidget);
  });

  testWidgets('quem convidou vê quem daquela lista já confirmou presença',
      (tester) async {
    final repo = MockInviteRepository();
    await _pump(tester, repo);

    // "Já convidado" sozinho não distinguiria convite sem resposta de convite
    // atendido, e quem convidou ficaria sem saber se precisa chamar mais gente.
    expect(find.text('Confirmou presença'), findsOneWidget);
    final dora = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Dora'),
    );
    expect(dora.onChanged, isNull);
  });

  testWidgets('falha parcial nomeia quem ficou de fora e oferece repetir',
      (tester) async {
    final repo = MockInviteRepository();
    when(() => repo.invite(_actionId, 'g1', any())).thenAnswer((_) async => const [
          InviteResult(userId: 'u1', outcome: InviteOutcome.created),
          InviteResult(userId: 'u2', outcome: InviteOutcome.notInGroup),
        ]);
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ana'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Bruno'));
    await tester.pump();
    await tester.tap(find.textContaining('Convidar ('));
    await tester.pumpAndSettle();

    // Nominalmente: quem ficou de fora tem nome, não é "1 falhou".
    expect(find.textContaining('Bruno'), findsWidgets);
    expect(find.textContaining('Ficaram de fora'), findsOneWidget);
    // E o botão vira "tentar de novo" só com quem falhou.
    expect(find.textContaining('Tentar de novo (1)'), findsOneWidget);
  });

  testWidgets('rede caindo não afirma sucesso', (tester) async {
    final repo = MockInviteRepository();
    when(() => repo.invite(_actionId, 'g1', any()))
        .thenThrow(Exception('sem rede'));
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ana'));
    await tester.pump();
    await tester.tap(find.textContaining('Convidar ('));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ficaram de fora: Ana'), findsOneWidget);
    expect(find.textContaining('0 enviado'), findsOneWidget);
  });
}

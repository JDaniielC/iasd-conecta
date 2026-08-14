import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/invite/domain/action_invite.dart';
import 'package:iasd_conecta/features/invite/invite_providers.dart';
import 'package:iasd_conecta/features/invite/presentation/received_invites_page.dart';

/// Change `convite-para-acao` — a tela de convites recebidos, em 360 px.
///
/// O caso menos óbvio é o do Grupo que a pessoa deixou: o convite CONTINUA na
/// lista (já foi entregue; retirá-lo em silêncio confundiria mais), mas aquele
/// Grupo some das opções de filtro. As duas metades juntas são a regra.

final _agora = DateTime(2026, 8, 13, 12);

Action _acao(String id, String nome) => Action(
      id: id,
      name: nome,
      dateTime: DateTime(2027, 1, 1, 10),
      local: 'Sede',
      creatorId: 'u9',
      createdAt: DateTime(2026, 1, 1),
    );

ReceivedInvite _convite({
  required String actionId,
  required String actionName,
  required String groupId,
  required String groupName,
  Action? acao,
  bool semAcao = false,
  bool confirmada = false,
}) =>
    ReceivedInvite(
      invite: ActionInvite(
        actionId: actionId,
        invitedId: 'eu',
        groupId: groupId,
        inviterId: 'u9',
        createdAt: DateTime(2026, 8, 12),
      ),
      groupName: groupName,
      action: semAcao ? null : (acao ?? _acao(actionId, actionName)),
      alreadyConfirmed: confirmada,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<ReceivedInvite> convites,
  Set<String> meusGrupos = const {'g1', 'g2', 'g3'},
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        receivedInvitesProvider.overrideWith((ref) async => convites),
        myGroupIdsProvider.overrideWith((ref) async => meusGrupos),
        clockProvider.overrideWithValue(() => _agora),
      ],
      child: const MaterialApp(home: ReceivedInvitesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sem convite, a tela explica de onde eles chegam e não mostra '
      'filtro', (tester) async {
    await _pump(tester, convites: const []);
    expect(find.textContaining('Convites chegam de pessoas dos seus Grupos'),
        findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
  });

  testWidgets('cada convite diz por qual Grupo veio', (tester) async {
    await _pump(tester, convites: [
      _convite(
          actionId: 'a1',
          actionName: 'Ensaio',
          groupId: 'g1',
          groupName: 'Jovens'),
    ]);
    expect(find.text('Ensaio'), findsOneWidget);
    expect(find.text('pelo Grupo Jovens'), findsOneWidget);
  });

  testWidgets('filtrar por um Grupo reduz a lista, e a contagem bate com o que '
      'está na tela', (tester) async {
    await _pump(tester, convites: [
      _convite(actionId: 'a1', actionName: 'Ensaio', groupId: 'g1', groupName: 'Jovens'),
      _convite(actionId: 'a2', actionName: 'Culto', groupId: 'g2', groupName: 'Musica'),
      _convite(actionId: 'a3', actionName: 'Visita', groupId: 'g3', groupName: 'Diaconia'),
    ]);

    expect(find.text('3 convite(s) em aberto'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Musica'));
    await tester.pumpAndSettle();

    expect(find.text('1 convite(s) em aberto'), findsOneWidget);
    expect(find.text('Culto'), findsOneWidget);
    expect(find.text('Ensaio'), findsNothing);
  });

  testWidgets('convite de Grupo que a pessoa deixou fica na lista, mas some '
      'das opções de filtro', (tester) async {
    await _pump(
      tester,
      convites: [
        _convite(actionId: 'a1', actionName: 'Ensaio', groupId: 'g1', groupName: 'Jovens'),
        _convite(actionId: 'a2', actionName: 'Culto', groupId: 'gx', groupName: 'Saiu Deste'),
      ],
      meusGrupos: const {'g1'},
    );

    expect(find.text('Culto'), findsOneWidget, reason: 'o convite já foi entregue');
    expect(find.text('2 convite(s) em aberto'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Saiu Deste'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Jovens'), findsOneWidget);
  });

  testWidgets('convite de Ação cancelada, encerrada ou ilegível não entra na '
      'lista', (tester) async {
    await _pump(tester, convites: [
      _convite(
        actionId: 'a1',
        actionName: 'Cancelada',
        groupId: 'g1',
        groupName: 'Jovens',
        acao: Action(
          id: 'a1',
          name: 'Cancelada',
          dateTime: DateTime(2027, 1, 1),
          local: 'Sede',
          creatorId: 'u9',
          createdAt: DateTime(2026, 1, 1),
          cancelledAt: DateTime(2026, 8, 12),
        ),
      ),
      _convite(
        actionId: 'a2',
        actionName: 'Encerrada',
        groupId: 'g1',
        groupName: 'Jovens',
        acao: _acao('a2', 'Encerrada').copyWithDateTime(DateTime(2026, 8, 13, 5)),
      ),
      // Ação restrita ao Grupo depois que a pessoa saiu dele: o banco não
      // devolve a linha e o embed vem nulo.
      _convite(
        actionId: 'a3',
        actionName: 'Ilegivel',
        groupId: 'g1',
        groupName: 'Jovens',
        semAcao: true,
      ),
    ]);

    expect(find.textContaining('Convites chegam'), findsOneWidget);
    expect(find.text('Cancelada'), findsNothing);
    expect(find.text('Encerrada'), findsNothing);
  });
}

extension on Action {
  Action copyWithDateTime(DateTime d) => Action(
        id: id,
        name: name,
        dateTime: d,
        local: local,
        creatorId: creatorId,
        createdAt: createdAt,
      );
}

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';
import 'package:iasd_conecta/features/action/presentation/create_action_page.dart';
import 'package:iasd_conecta/features/action/presentation/create_candidate_page.dart';
import 'package:iasd_conecta/features/action/voting_round_providers.dart';
import 'package:iasd_conecta/features/group/domain/group_category.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:iasd_conecta/features/suggested_action/suggested_action_providers.dart';

/// Change `acao-direcionada-a-grupo` — o controle de restrição na tela de
/// propor candidata, julgado na largura de celular.
///
/// A largura é 360, não a do desktop: o texto explicativo do controle é longo
/// de propósito (ele precisa dizer que a lista de quem vai some junto), e é
/// exatamente esse tipo de subtítulo que empurra formulário para rolagem
/// horizontal. O Flutter transforma estouro de layout em falha de teste, então
/// renderizar nessa largura já é a asserção.

const _roundId = 'r1';

Widget _app() {
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('quem-propoe'),
      votingRoundProvider(_roundId).overrideWith(
        (ref) async => VotingRound(
          id: _roundId,
          groupId: 'g1',
          openedBy: 'dona',
          deadline: DateTime(2027, 1, 1),
        ),
      ),
      suggestionsForGroupProvider('g1').overrideWith((ref) async => const []),
    ],
    child: const MaterialApp(
      home: CreateCandidatePage(votingRoundId: _roundId),
    ),
  );
}

void main() {
  testWidgets('o controle de restrição cabe na largura de celular, sem estouro',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Só para quem participa do Grupo'), findsOneWidget);
    // Rolagem é vertical; nada pode escapar na horizontal.
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.vertical);
  });

  testWidgets('a restrição nasce desmarcada — Ação de Grupo é pública por padrão',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Só para quem participa do Grupo'),
    );
    expect(tile.value, isFalse);
  });

  testWidgets(
    'criar Ação avulsa não oferece restrição — ali não há Grupo a que se referir',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('criador-1'),
            publicProfileProvider('criador-1').overrideWith(
              (ref) async =>
                  const PublicProfile(id: 'criador-1', displayName: 'Quem cria'),
            ),
            groupCategoriesProvider.overrideWith((ref) async => <GroupCategory>[]),
          ],
          child: const MaterialApp(home: CreateActionPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Toda Ação criada por aqui é avulsa: `acoes_candidata_checar_regras`
      // recusa `grupo_id` sem `rodada_id`. Um controle de restrição nesta tela
      // não teria Grupo a que se referir, e o `check`
      // `acoes_restrita_exige_grupo` recusaria a escrita. Sem este teste, um
      // controle acrescentado aqui passaria por todos os gates.
      expect(find.text('Só para quem participa do Grupo'), findsNothing);
      expect(find.textContaining('participa do Grupo'), findsNothing);
    },
  );
}

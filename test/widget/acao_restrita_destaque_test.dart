import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/data/actions_seen_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_list_page.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';

/// Change `acao-direcionada-a-grupo`, task 6.1 — a faixa de destaque não
/// reintroduz a Ação restrita.
///
/// `destaque-de-acoes-distritais-e-de-grupo` já está aplicada, então esta
/// verificação é obrigatória, não opcional. O design afirma que a faixa herda
/// o filtro de graça, porque a policy corta na origem e a faixa é montada a
/// partir da mesma lista. Afirmação a provar.
///
/// O primeiro teste alimenta a tela com uma Ação restrita de um Grupo que NÃO
/// está em `myGroupIds` — uma situação que a RLS torna impossível de verdade.
/// Ele é montado assim de propósito: se um dia a faixa passar a se alimentar de
/// outro lugar, ou parar de olhar `myGroupIds`, é aqui que aparece. Um teste
/// que só usasse dado possível não protegeria de nada.

class FakeActionsSeenRepository implements ActionsSeenRepository {
  FakeActionsSeenRepository(this.stored);
  DateTime? stored;

  @override
  Future<DateTime?> readLastSeenActionsDate() async => stored;

  @override
  Future<void> writeLastSeenActionsDate(DateTime date) async => stored = date;
}

const _churches = [Church(id: 'igreja-1', name: 'Central')];
final _now = DateTime(2026, 8, 12, 12, 0);
final _futura = DateTime(2026, 8, 20, 19, 0);
final _marcador = DateTime(2026, 8, 10, 8, 0);
final _depoisDoMarcador = DateTime(2026, 8, 11, 8, 0);

ActionWithChurch _restrita({required String id, required String name, required String groupId}) {
  return ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: id,
      name: name,
      dateTime: _futura,
      local: 'Templo',
      creatorId: 'dono-1',
      createdAt: _depoisDoMarcador,
      groupId: groupId,
      restrictedToGroup: true,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ActionWithChurch> actions,
  Set<String> myGroupIds = const <String>{},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        actionsWithChurchProvider.overrideWith((ref) async => actions),
        churchesProvider.overrideWith((ref) async => _churches),
        clockProvider.overrideWithValue(() => _now),
        myGroupIdsProvider.overrideWith((ref) async => myGroupIds),
        actionsSeenRepositoryProvider
            .overrideWithValue(FakeActionsSeenRepository(_marcador)),
      ],
      child: const MaterialApp(home: ActionListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ação restrita de Grupo alheio não entra na faixa de destaque',
      (tester) async {
    await _pump(
      tester,
      actions: [_restrita(id: 'a1', name: 'Reunião interna', groupId: 'g-alheio')],
      myGroupIds: const {'g-meu'},
    );

    expect(find.text('Em destaque'), findsNothing);
    expect(find.text('Novo no seu Grupo'), findsNothing);
  });

  testWidgets('a marca de restrita aparece nos dois lugares onde quem participa '
      'encontra a Ação', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      actions: [_restrita(id: 'a1', name: 'Reunião interna', groupId: 'g-meu')],
      myGroupIds: const {'g-meu'},
    );

    // Na lista por período cabe texto; a linha quebra em vez de cortar.
    expect(find.textContaining('Só do Grupo'), findsOneWidget);
    // Na faixa de destaque a linha de data é `maxLines: 1`, então é ícone —
    // com o rótulo que o leitor de tela anuncia.
    expect(
      find.byTooltip('Só para quem participa do Grupo'),
      findsOneWidget,
    );
  });

  testWidgets('Ação pública não ganha marca nenhuma', (tester) async {
    await _pump(
      tester,
      actions: [
        ActionWithChurch(
          churchId: 'igreja-1',
          action: Action(
            id: 'a1',
            name: 'Encontro aberto',
            dateTime: _futura,
            local: 'Templo',
            creatorId: 'dono-1',
            createdAt: _depoisDoMarcador,
            groupId: 'g-meu',
          ),
        ),
      ],
      myGroupIds: const {'g-meu'},
    );

    expect(find.textContaining('Só do Grupo'), findsNothing);
    expect(find.byTooltip('Só para quem participa do Grupo'), findsNothing);
  });

  testWidgets('para quem participa, a Ação restrita entra no destaque como '
      'qualquer Ação do Grupo', (tester) async {
    await _pump(
      tester,
      actions: [_restrita(id: 'a1', name: 'Reunião interna', groupId: 'g-meu')],
      myGroupIds: const {'g-meu'},
    );

    expect(find.text('Em destaque'), findsOneWidget);
    expect(find.text('Novo no seu Grupo'), findsOneWidget);
    // Uma vez na faixa, outra na lista por período.
    expect(find.text('Reunião interna'), findsNWidgets(2));
  });
}

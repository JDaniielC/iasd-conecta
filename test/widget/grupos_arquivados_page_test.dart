import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/archived_groups_page.dart';
import 'package:mocktail/mocktail.dart';

/// `ArchivedGroupsPage` — FR-019/FR-022, a tela de consertar engano. Estava em
/// 1/38 linhas até a change `cobertura-e-tdd`.
/// Julgada na largura de celular (360).

class MockGroupRepository extends Mock implements GroupRepository {}

Group _archived(String id, String name, DateTime archivedAt) => Group(
      id: id,
      name: name,
      category: 'Ministério Jovem',
      schedule: 'sábados 6h',
      location: 'Praça Central',
      ownerId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
      archivedAt: archivedAt,
    );

Widget _app({
  required List<Group> groups,
  GroupRepository? repository,
  Object? error,
}) {
  return ProviderScope(
    overrides: [
      groupRepositoryProvider.overrideWithValue(repository ?? MockGroupRepository()),
      archivedGroupsProvider.overrideWith(
        (ref) async => error != null ? throw error : groups,
      ),
    ],
    child: const MaterialApp(home: ArchivedGroupsPage()),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cada Grupo arquivado mostra quando foi arquivado', (tester) async {
    await _pump(
      tester,
      _app(groups: [_archived('g1', 'SevenBikers', DateTime(2026, 3, 7))]),
    );

    expect(find.text('SevenBikers'), findsOneWidget);
    // Dia e mês com dois dígitos — é o que permite decidir se desarquiva.
    expect(find.text('Arquivado em 07/03/2026'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Desarquivar'), findsOneWidget);
  });

  testWidgets('sem Grupo arquivado, diz isso em vez de tela em branco', (tester) async {
    await _pump(tester, _app(groups: const []));

    expect(find.text('Nenhum Grupo/Ministério arquivado.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Desarquivar'), findsNothing);
  });

  testWidgets('falha de carregamento avisa sem dizer que não há arquivados',
      (tester) async {
    await _pump(tester, _app(groups: const [], error: StateError('falha de rede')));

    expect(find.text('Não deu pra carregar agora.'), findsOneWidget);
    expect(find.text('Nenhum Grupo/Ministério arquivado.'), findsNothing);
  });

  group('FR-022: a confirmação é honesta sobre o que NÃO volta', () {
    testWidgets('o aviso diz o que volta e o que não volta', (tester) async {
      await _pump(
        tester,
        _app(groups: [_archived('g1', 'SevenBikers', DateTime(2026, 3, 7))]),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Desarquivar'));
      await tester.pumpAndSettle();

      expect(find.text('Desarquivar este Grupo/Ministério?'), findsOneWidget);
      expect(
        find.textContaining('Ele volta à lista e os participantes voltam junto.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('As Ações que foram canceladas NÃO voltam'),
        findsOneWidget,
      );
      expect(
        find.textContaining('as Rodadas de votação encerradas continuam encerradas'),
        findsOneWidget,
      );
    });

    testWidgets('desistir não desarquiva nada', (tester) async {
      final repository = MockGroupRepository();
      await _pump(
        tester,
        _app(
          groups: [_archived('g1', 'SevenBikers', DateTime(2026, 3, 7))],
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Desarquivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Desistir'));
      await tester.pumpAndSettle();

      verifyNever(() => repository.unarchiveGroup(any()));
      expect(find.text('SevenBikers'), findsOneWidget);
    });

    testWidgets('confirmar desarquiva aquele Grupo', (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.unarchiveGroup(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        _app(
          groups: [_archived('g1', 'SevenBikers', DateTime(2026, 3, 7))],
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Desarquivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Desarquivar'));
      await tester.pumpAndSettle();

      verify(() => repository.unarchiveGroup('g1')).called(1);
    });

    testWidgets('recusa do banco avisa em vez de sumir com o Grupo da lista',
        (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.unarchiveGroup(any())).thenThrow(StateError('recusado'));

      await _pump(
        tester,
        _app(
          groups: [_archived('g1', 'SevenBikers', DateTime(2026, 3, 7))],
          repository: repository,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Desarquivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Desarquivar'));
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra desarquivar agora.'), findsOneWidget);
      expect(find.text('SevenBikers'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/group/domain/group_category.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/suggested_action/data/suggested_action_repository.dart';
import 'package:iasd_conecta/features/suggested_action/domain/suggested_action.dart';
import 'package:iasd_conecta/features/suggested_action/presentation/manage_suggested_actions_page.dart';
import 'package:iasd_conecta/features/suggested_action/suggested_action_providers.dart';
import 'package:mocktail/mocktail.dart';

/// `ManageSuggestedActionsPage` — estava em 1/67 linhas até a change
/// `cobertura-e-tdd`. Julgada na largura de celular (360).

class MockSuggestedActionRepository extends Mock implements SuggestedActionRepository {}

const _categories = [
  GroupCategory(id: 'cat1', name: 'Ministério Jovem'),
  GroupCategory(id: 'cat2', name: 'Ministério da Música'),
];

const _suggestions = [
  SuggestedAction(id: 's1', categoryId: 'cat1', name: 'Visita ao Lar'),
  SuggestedAction(id: 's2', categoryId: 'cat2', name: 'Ensaio aberto'),
];

Widget _app({
  SuggestedActionRepository? repository,
  List<SuggestedAction> suggestions = _suggestions,
  Object? categoriesError,
  Object? suggestionsError,
}) {
  return ProviderScope(
    overrides: [
      suggestedActionRepositoryProvider
          .overrideWithValue(repository ?? MockSuggestedActionRepository()),
      groupCategoriesProvider.overrideWith(
        (ref) async => categoriesError != null ? throw categoriesError : _categories,
      ),
      allSuggestedActionsProvider.overrideWith(
        (ref) async => suggestionsError != null ? throw suggestionsError : suggestions,
      ),
    ],
    child: const MaterialApp(home: ManageSuggestedActionsPage()),
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

Future<void> _chooseCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista cada sugestão com a Categoria dela por extenso', (tester) async {
    await _pump(tester, _app());

    expect(find.widgetWithText(ListTile, 'Visita ao Lar'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Ensaio aberto'), findsOneWidget);
    // O subtítulo traduz categoria_id em nome — id cru na tela não serve
    // para o Administrador decidir nada.
    expect(find.text('Ministério Jovem'), findsWidgets);
    expect(find.text('cat1'), findsNothing);
  });

  group('Cadastrar', () {
    testWidgets('sem nome nem Categoria, recusa e diz o que falta', (tester) async {
      final repository = MockSuggestedActionRepository();
      await _pump(tester, _app(repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
      await tester.pumpAndSettle();

      expect(find.text('Escolha uma Categoria e informe um nome.'), findsOneWidget);
      verifyNever(() => repository.create(
            categoryId: any(named: 'categoryId'),
            name: any(named: 'name'),
          ));
    });

    testWidgets('com nome mas sem Categoria, também recusa', (tester) async {
      final repository = MockSuggestedActionRepository();
      await _pump(tester, _app(repository: repository));

      await tester.enterText(find.byType(TextField), 'Café missionário');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
      await tester.pumpAndSettle();

      expect(find.text('Escolha uma Categoria e informe um nome.'), findsOneWidget);
      verifyNever(() => repository.create(
            categoryId: any(named: 'categoryId'),
            name: any(named: 'name'),
          ));
    });

    testWidgets('com Categoria e nome, cadastra e limpa o campo', (tester) async {
      final repository = MockSuggestedActionRepository();
      when(() => repository.create(
            categoryId: any(named: 'categoryId'),
            name: any(named: 'name'),
          )).thenAnswer((_) async {});

      await _pump(tester, _app(repository: repository));
      await _chooseCategory(tester, 'Ministério Jovem');
      await tester.enterText(find.byType(TextField), '  Café missionário  ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
      await tester.pumpAndSettle();

      // O nome vai aparado — espaço nas pontas não é parte do nome.
      verify(() => repository.create(categoryId: 'cat1', name: 'Café missionário'))
          .called(1);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('cadastro recusado avisa e não limpa o que foi digitado',
        (tester) async {
      final repository = MockSuggestedActionRepository();
      when(() => repository.create(
            categoryId: any(named: 'categoryId'),
            name: any(named: 'name'),
          )).thenThrow(StateError('recusado'));

      await _pump(tester, _app(repository: repository));
      await _chooseCategory(tester, 'Ministério Jovem');
      await tester.enterText(find.byType(TextField), 'Café missionário');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Adicionar'));
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra cadastrar agora.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Café missionário');
    });
  });

  group('Remover', () {
    testWidgets('a lixeira remove aquela sugestão', (tester) async {
      final repository = MockSuggestedActionRepository();
      when(() => repository.delete(any())).thenAnswer((_) async {});

      await _pump(tester, _app(repository: repository));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      verify(() => repository.delete('s1')).called(1);
    });

    testWidgets('remoção recusada avisa e a sugestão continua na lista',
        (tester) async {
      final repository = MockSuggestedActionRepository();
      when(() => repository.delete(any())).thenThrow(StateError('recusado'));

      await _pump(tester, _app(repository: repository));
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra remover agora.'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Visita ao Lar'), findsOneWidget);
    });
  });

  group('Caminhos de falha do carregamento', () {
    testWidgets('categorias que não carregam avisam', (tester) async {
      await _pump(tester, _app(categoriesError: StateError('falha de rede')));

      expect(find.text('Não deu pra carregar as categorias.'), findsWidgets);
    });

    testWidgets('sugestões que não carregam avisam sem derrubar o formulário',
        (tester) async {
      await _pump(tester, _app(suggestionsError: StateError('falha de rede')));

      expect(find.text('Não deu pra carregar as sugestões.'), findsOneWidget);
      // O cadastro continua possível.
      expect(find.widgetWithText(ElevatedButton, 'Adicionar'), findsOneWidget);
    });

    testWidgets('lista vazia não inventa sugestão nenhuma', (tester) async {
      await _pump(tester, _app(suggestions: const []));

      expect(find.byType(ListTile), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });
}

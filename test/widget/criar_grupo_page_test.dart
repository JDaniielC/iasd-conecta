import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/domain/group_category.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/create_group_page.dart';
import 'package:mocktail/mocktail.dart';

/// `CreateGroupPage` — estava em 1/74 linhas até a change `cobertura-e-tdd`.
/// Julgada na largura de celular (360).

class MockGroupRepository extends Mock implements GroupRepository {}

class _FakeNewGroup extends Fake implements NewGroup {}

const _categories = [
  GroupCategory(id: 'cat1', name: 'Ministério Jovem'),
  GroupCategory(id: 'cat2', name: 'Ministério da Música'),
];

Widget _app({
  GroupRepository? repository,
  List<GroupCategory> categories = _categories,
  Object? categoriesError,
}) {
  final router = GoRouter(
    initialLocation: '/grupos/novo',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('tela anterior')),
      GoRoute(path: '/grupos/novo', builder: (_, _) => const CreateGroupPage()),
    ],
  );

  return ProviderScope(
    overrides: [
      groupRepositoryProvider.overrideWithValue(repository ?? MockGroupRepository()),
      groupCategoriesProvider.overrideWith(
        (ref) async => categoriesError != null ? throw categoriesError : categories,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  setUpAll(() => registerFallbackValue(_FakeNewGroup()));

  testWidgets('o formulário pede nome, Categoria e detalhes opcionais', (tester) async {
    await _pump(tester, _app());

    expect(_field('Nome do Grupo/Ministério'), findsOneWidget);
    expect(_field('Categoria'), findsOneWidget);
    expect(_field('Detalhes (opcional)'), findsOneWidget);
    expect(find.text('Escolha uma sugestão ou digite livremente'), findsOneWidget);
  });

  group('Validação: nada incompleto chega ao banco', () {
    testWidgets('formulário vazio recusa e diz o que falta', (tester) async {
      final repository = MockGroupRepository();
      await _pump(tester, _app(repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um nome'), findsOneWidget);
      expect(find.text('Informe uma Categoria'), findsOneWidget);
      expect(find.text('Preencha nome e Categoria.'), findsOneWidget);
      verifyNever(() => repository.createGroup(any()));
    });

    testWidgets('nome só com espaços não conta como nome', (tester) async {
      final repository = MockGroupRepository();
      await _pump(tester, _app(repository: repository));

      await tester.enterText(_field('Nome do Grupo/Ministério'), '   ');
      await tester.enterText(_field('Categoria'), 'Ministério Jovem');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um nome'), findsOneWidget);
      verifyNever(() => repository.createGroup(any()));
    });

    testWidgets('nome sem Categoria também recusa', (tester) async {
      final repository = MockGroupRepository();
      await _pump(tester, _app(repository: repository));

      await tester.enterText(_field('Nome do Grupo/Ministério'), 'SevenBikers');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      expect(find.text('Informe uma Categoria'), findsOneWidget);
      verifyNever(() => repository.createGroup(any()));
    });
  });

  group('Sugestão de Categoria', () {
    testWidgets('digitar filtra as Categorias que existem', (tester) async {
      await _pump(tester, _app());

      await tester.enterText(_field('Categoria'), 'Música');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Ministério da Música'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Ministério Jovem'), findsNothing);
    });

    testWidgets('escolher a sugestão preenche o campo', (tester) async {
      await _pump(tester, _app());

      await tester.enterText(_field('Categoria'), 'Jovem');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Ministério Jovem'));
      await tester.pumpAndSettle();

      expect(_field('Ministério Jovem'), findsOneWidget);
    });

    testWidgets('Categoria livre continua aceita — a sugestão não é uma lista fechada',
        (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.createGroup(any())).thenAnswer((_) async => 'g-novo');
      await _pump(tester, _app(repository: repository));

      await tester.enterText(_field('Nome do Grupo/Ministério'), 'SevenBikers');
      await tester.enterText(_field('Categoria'), 'Ciclismo Missionário');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      final captured =
          verify(() => repository.createGroup(captureAny())).captured.single as NewGroup;
      expect(captured.category, 'Ciclismo Missionário');
    });

    testWidgets('Categorias que não carregam não travam o formulário', (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.createGroup(any())).thenAnswer((_) async => 'g-novo');
      await _pump(tester, _app(
        repository: repository,
        categoriesError: StateError('falha de rede'),
      ));

      // O campo vira texto puro, e criar Grupo continua possível.
      await tester.enterText(_field('Nome do Grupo/Ministério'), 'SevenBikers');
      await tester.enterText(_field('Categoria'), 'Ciclismo Missionário');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      verify(() => repository.createGroup(any())).called(1);
    });
  });

  group('Envio', () {
    testWidgets('formulário completo envia nome, Categoria e detalhes', (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.createGroup(any())).thenAnswer((_) async => 'g-novo');
      await _pump(tester, _app(repository: repository));

      await tester.enterText(_field('Nome do Grupo/Ministério'), 'SevenBikers');
      await tester.enterText(_field('Categoria'), 'Ministério Jovem');
      await tester.enterText(_field('Detalhes (opcional)'), 'Pedal aos domingos');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      final captured =
          verify(() => repository.createGroup(captureAny())).captured.single as NewGroup;
      expect(captured.name, 'SevenBikers');
      expect(captured.category, 'Ministério Jovem');
      expect(captured.details, 'Pedal aos domingos');
    });

    testWidgets('falha de escrita avisa e o botão volta a ficar disponível',
        (tester) async {
      final repository = MockGroupRepository();
      when(() => repository.createGroup(any())).thenThrow(StateError('falha de rede'));
      await _pump(tester, _app(repository: repository));

      await tester.enterText(_field('Nome do Grupo/Ministério'), 'SevenBikers');
      await tester.enterText(_field('Categoria'), 'Ministério Jovem');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'));
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra criar o Grupo agora. Tente de novo.'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Criar Grupo/Ministério'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}

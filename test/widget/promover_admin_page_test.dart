import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/district_admin/data/district_admin_repository.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/district_admin/presentation/promote_admin_page.dart';
import 'package:mocktail/mocktail.dart';

/// `PromoteAdminPage` — estava em 1/36 linhas até a change `cobertura-e-tdd`.
/// Julgada na largura de celular (360).

class MockDistrictAdminRepository extends Mock implements DistrictAdminRepository {}

Widget _app(DistrictAdminRepository repository) {
  return ProviderScope(
    overrides: [districtAdminRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: PromoteAdminPage()),
  );
}

Future<void> _pump(WidgetTester tester, DistrictAdminRepository repository) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_app(repository));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tela avisa que Perfil sozinho não basta', (tester) async {
    await _pump(tester, MockDistrictAdminRepository());

    expect(
      find.textContaining('precisa já ter Conta (upgrade de Perfil)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'ID do Perfil'), findsOneWidget);
  });

  testWidgets('sem ID, recusa e diz o que falta', (tester) async {
    final repository = MockDistrictAdminRepository();
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();

    expect(find.text('Informe o ID do Perfil.'), findsOneWidget);
    verifyNever(() => repository.promoteToAdmin(any()));
  });

  testWidgets('ID só com espaços também não conta como ID', (tester) async {
    final repository = MockDistrictAdminRepository();
    await _pump(tester, repository);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();

    expect(find.text('Informe o ID do Perfil.'), findsOneWidget);
    verifyNever(() => repository.promoteToAdmin(any()));
  });

  testWidgets('promoção bem-sucedida confirma e limpa o campo', (tester) async {
    final repository = MockDistrictAdminRepository();
    when(() => repository.promoteToAdmin(any())).thenAnswer((_) async {});

    await _pump(tester, repository);
    await tester.enterText(find.byType(TextField), '  perfil-123  ');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();

    verify(() => repository.promoteToAdmin('perfil-123')).called(1);
    expect(find.text('Promovido a Administrador do distrito.'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('recusa avisa, não confirma, e o ID digitado continua na tela',
      (tester) async {
    final repository = MockDistrictAdminRepository();
    when(() => repository.promoteToAdmin(any())).thenThrow(StateError('sem Conta'));

    await _pump(tester, repository);
    await tester.enterText(find.byType(TextField), 'perfil-123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Não deu pra promover. Confirme que o ID existe e que essa pessoa já tem Conta.',
      ),
      findsOneWidget,
    );
    expect(find.text('Promovido a Administrador do distrito.'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'perfil-123');
  });

  testWidgets('uma recusa depois de um sucesso apaga a confirmação anterior',
      (tester) async {
    final repository = MockDistrictAdminRepository();
    when(() => repository.promoteToAdmin('perfil-ok')).thenAnswer((_) async {});
    when(() => repository.promoteToAdmin('perfil-ruim')).thenThrow(StateError('sem Conta'));

    await _pump(tester, repository);

    await tester.enterText(find.byType(TextField), 'perfil-ok');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();
    expect(find.text('Promovido a Administrador do distrito.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'perfil-ruim');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Promover'));
    await tester.pumpAndSettle();

    // A confirmação da promoção anterior não pode continuar na tela ao lado
    // de um erro — leria como se as duas tivessem dado certo.
    expect(find.text('Promovido a Administrador do distrito.'), findsNothing);
  });
}

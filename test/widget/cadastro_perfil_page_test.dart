import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/core/providers.dart';
import 'package:iasd_distrito_vsa/features/perfil/data/perfil_repository.dart';
import 'package:iasd_distrito_vsa/features/perfil/domain/igreja.dart';
import 'package:iasd_distrito_vsa/features/perfil/presentation/cadastro_perfil_page.dart';
import 'package:mocktail/mocktail.dart';

class MockPerfilRepository extends Mock implements PerfilRepository {}

Future<void> _pumpPage(WidgetTester tester, PerfilRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        perfilRepositoryProvider.overrideWithValue(repo),
        igrejasProvider.overrideWith((ref) async => <Igreja>[]),
      ],
      child: const MaterialApp(home: CadastroPerfilPage()),
    ),
  );
  await tester.pumpAndSettle();
}

ElevatedButton _submitButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

void main() {
  late MockPerfilRepository repo;

  setUp(() => repo = MockPerfilRepository());

  testWidgets(
    'FR-003: botão de concluir fica desabilitado sem consentimento LGPD',
    (tester) async {
      await _pumpPage(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Ana Souza');
      await tester.enterText(find.widgetWithText(TextFormField, 'Idade'), '30');
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'botão habilita quando nome, idade e consentimento estão ok',
    (tester) async {
      await _pumpPage(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Ana Souza');
      await tester.enterText(find.widgetWithText(TextFormField, 'Idade'), '30');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'US2/FR-005: exige Apelido quando idade é abaixo de 18',
    (tester) async {
      await _pumpPage(tester, repo);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Maria Silva');
      await tester.enterText(find.widgetWithText(TextFormField, 'Idade'), '15');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      expect(
        find.widgetWithText(TextFormField, 'Apelido (obrigatório para menores de 18)'),
        findsOneWidget,
      );
      expect(_submitButton(tester).onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Apelido (obrigatório para menores de 18)'),
        'Mari',
      );
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
    },
  );
}

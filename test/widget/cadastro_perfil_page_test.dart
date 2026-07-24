import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/core/providers.dart';
import 'package:iasd_distrito_vsa/features/perfil/data/perfil_repository.dart';
import 'package:iasd_distrito_vsa/features/perfil/domain/church.dart';
import 'package:iasd_distrito_vsa/features/perfil/presentation/cadastro_perfil_page.dart';
import 'package:mocktail/mocktail.dart';

class MockPerfilRepository extends Mock implements PerfilRepository {}

const _igrejaTeste = Church(id: 'igreja-1', name: 'Igreja Teste');

Future<void> _pumpPage(
  WidgetTester tester,
  PerfilRepository repo, {
  List<Church> churches = const <Church>[],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        perfilRepositoryProvider.overrideWithValue(repo),
        churchesProvider.overrideWith((ref) async => churches),
      ],
      child: const MaterialApp(home: CadastroPerfilPage()),
    ),
  );
  await tester.pumpAndSettle();
}

ElevatedButton _submitButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

/// Rola o formulário até o Checkbox de consentimento antes de tocar nele —
/// a página cresceu com os links de Política de Privacidade/Termos de Uso
/// (integração da tarefa de LGPD) e o Checkbox nem sempre cabe na viewport
/// padrão de teste sem rolar.
Future<void> _tapConsentimento(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
}

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
      await _tapConsentimento(tester);
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
      await _tapConsentimento(tester);
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

  testWidgets(
    'LGPD art. 11 I: escolher Igreja de origem exige consentimento destacado separado',
    (tester) async {
      await _pumpPage(tester, repo, churches: const [_igrejaTeste]);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'Ana Souza');
      await tester.enterText(find.widgetWithText(TextFormField, 'Idade'), '30');
      await _tapConsentimento(tester);
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
      expect(find.byType(CheckboxListTile), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Igreja Teste').last);
      await tester.pumpAndSettle();

      // segundo checkbox destacado aparece (antes do geral na árvore, logo
      // após o seletor de Igreja), e o botão volta a desabilitar até ele
      // ser marcado.
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(_submitButton(tester).onPressed, isNull);

      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pump();

      expect(_submitButton(tester).onPressed, isNotNull);
    },
  );
}

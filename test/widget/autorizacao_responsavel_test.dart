import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/profile/data/profile_repository.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:iasd_conecta/features/profile/presentation/profile_signup_page.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

Future<void> _pumpSignupPage(
  WidgetTester tester,
  ProfileRepository repo, {
  List<Church> churches = const <Church>[],
}) async {
  // A tela cresceu com o passo do Responsável; sem viewport maior, os campos
  // ficam fora de alcance e os `tap` erram o alvo.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        churchesProvider.overrideWith((ref) async => churches),
      ],
      child: const MaterialApp(home: ProfileSignupPage()),
    ),
  );
  await tester.pumpAndSettle();
}

ElevatedButton _submitButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

/// Preenche o formulário com idade de criança — derivada da constante, nunca
/// literal, para o teste sobreviver a uma mudança de limiar.
Future<void> _fillChildForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'Ana Silva');
  await tester.enterText(
    find.byType(TextFormField).at(1),
    '${childAgeThreshold - 1}',
  );
  await tester.pumpAndSettle();
}

/// Acha cada caixa pelo TEXTO, nunca por índice de `CheckboxListTile`: criança
/// com Igreja de origem tem três caixas na árvore, e índice vira um jogo que
/// quebra na próxima feature.
Future<void> _tapCheckboxContaining(WidgetTester tester, String text) async {
  final finder = find.ancestor(
    of: find.textContaining(text),
    matching: find.byType(CheckboxListTile),
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late MockProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const Profile(
        name: '',
        gender: Gender.female,
        age: 0,
        lgpdConsentAccepted: false,
      ),
    );
  });

  setUp(() {
    repo = MockProfileRepository();
    when(() => repo.createProfile(any())).thenAnswer((_) async {});
  });

  testWidgets(
    'FR-001/FR-002: abaixo do limiar aparecem os dois campos e a caixa',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await _fillChildForm(tester);

      expect(find.text('Nome do responsável'), findsOneWidget);
      expect(find.text('E-mail ou telefone do responsável'), findsOneWidget);
      expect(
        find.textContaining('Sou responsável por esta criança'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FR-005/SC-003: acima do limiar, o passo não existe',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await tester.enterText(find.byType(TextFormField).at(0), 'Carla Souza');
      await tester.enterText(find.byType(TextFormField).at(1), '30');
      await tester.pumpAndSettle();

      expect(find.text('Nome do responsável'), findsNothing);
      expect(
        find.textContaining('Sou responsável por esta criança'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'FR-002: marcar só o consentimento LGPD comum não habilita o botão',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await _fillChildForm(tester);
      await _tapCheckboxContaining(tester, 'Li e aceito o uso dos meus dados');

      // As duas são independentes e recusáveis em separado — é isso que faz a
      // autorização ser "destacada" no sentido do art. 14.
      expect(_submitButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'FR-001/FR-004: sem nome ou sem contato, o botão não habilita',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await _fillChildForm(tester);
      await _tapCheckboxContaining(tester, 'Li e aceito o uso dos meus dados');
      await _tapCheckboxContaining(tester, 'Sou responsável por esta criança');
      await tester.enterText(find.byType(TextFormField).at(2), 'Ninho');
      await tester.pumpAndSettle();

      // Caixa marcada, Apelido posto, e ainda assim travado: falta dizer QUEM
      // autorizou. Marcar sem nome não demonstra nada.
      expect(_submitButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'FR-003/FR-006: o texto diz o que é autorizado e que a identidade não é '
    'verificada',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await _fillChildForm(tester);

      expect(find.textContaining('incluindo o Apelido e a Igreja de origem'),
          findsOneWidget);
      expect(
        find.textContaining('não verifica a identidade de quem marca'),
        findsOneWidget,
      );
      // E o contato é registro, não canal — a tela precisa dizer isso onde a
      // pessoa digita, não só na Política.
      expect(
        find.textContaining('o app não escreve para este contato'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FR-008: subir a idade acima do limiar limpa o passo',
    (tester) async {
      await _pumpSignupPage(tester, repo);
      await _fillChildForm(tester);
      await tester.enterText(find.byType(TextFormField).at(2), 'Maria Silva');
      await _tapCheckboxContaining(tester, 'Sou responsável por esta criança');

      await tester.enterText(find.byType(TextFormField).at(1), '30');
      await tester.pumpAndSettle();
      expect(find.text('Nome do responsável'), findsNothing);

      // E ao voltar para idade de criança, a caixa está desmarcada de novo —
      // senão o estado antigo sobreviveria escondido.
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '${childAgeThreshold - 1}',
      );
      await tester.pumpAndSettle();
      final checkbox = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.textContaining('Sou responsável por esta criança'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.value, isFalse);
    },
  );
}

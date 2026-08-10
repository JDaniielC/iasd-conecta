import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/legal/presentation/privacy_policy_page.dart';

/// Feature 016, US3 — a Política deixa de descrever uma ausência.
///
/// Este arquivo existe para que as duas frases não voltem numa edição futura.
/// Enquanto a tela existir e o texto disser que ela não existe, o app está
/// descrevendo errado a si mesmo — que a constituição trata como violação, não
/// como detalhe de redação.
Future<void> pumpPolicy(WidgetTester tester, {bool hasProfile = true}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => hasProfile),
      ],
      child: const MaterialApp(home: PrivacyPolicyPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Junta todo o texto renderizado — as frases proibidas estão espalhadas em
/// vários widgets, e procurar por uma só não provaria nada.
String renderedText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .join(' ');
}

void main() {
  testWidgets(
    'FR-014/SC-006: as frases que dizem que a tela não existe sumiram',
    (tester) async {
      await pumpPolicy(tester);
      final text = renderedText(tester);

      expect(text.contains('ainda não existe uma tela própria'), isFalse);
      expect(text.contains('enquanto não existe tela de edição de perfil'),
          isFalse);
    },
  );

  testWidgets('FR-014: a Política aponta para "Meu Perfil"', (tester) async {
    await pumpPolicy(tester);

    expect(renderedText(tester).contains('Meu Perfil'), isTrue);
  });

  testWidgets(
    'FR-014: continua dizendo que gênero e idade são por e-mail — a Política '
    'descreve o app inclusive no que ele ainda não faz',
    (tester) async {
      await pumpPolicy(tester);
      final text = renderedText(tester);

      expect(text.contains('Gênero e idade continuam sendo corrigidos por '
          'e-mail'), isTrue);
    },
  );

  testWidgets('FR-006: quem tem Perfil encontra o caminho até a tela', (
    tester,
  ) async {
    await pumpPolicy(tester);

    expect(find.text('Abrir Meu Perfil'), findsOneWidget);
  });
}

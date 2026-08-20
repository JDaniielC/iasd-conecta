import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/legal/legal_metadata.dart';
import 'package:iasd_conecta/features/legal/presentation/terms_of_use_page.dart';

/// `TermsOfUsePage` — estava em 1/14 linhas. A Política de Privacidade já tinha
/// teste (`politica_privacidade_perfil_test.dart`); os Termos, não, e são o
/// documento sob o qual o consentimento é carimbado.
/// Julgada na largura de celular (360).

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(home: TermsOfUsePage()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a versão vigente aparece na tela, com a data', (tester) async {
    await _pump(tester);

    // A pessoa precisa conseguir dizer QUAL texto ela leu — é o que o banco
    // carimba em `consentimento_lgpd_versao`.
    expect(
      find.text(
        'Versão ${LegalMetadata.version} — vigente desde ${LegalMetadata.effectiveDate}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a tela se identifica como Termos de Uso', (tester) async {
    await _pump(tester);

    expect(find.widgetWithText(AppBar, 'Termos de Uso'), findsOneWidget);
    expect(find.text('Rede IASD Vitória de Santo Antão'), findsOneWidget);
  });

  testWidgets('diz o que vale para quem só navega sem se cadastrar',
      (tester) async {
    await _pump(tester);

    expect(
      find.textContaining('Se você só navega sem se cadastrar (Visitante)'),
      findsOneWidget,
    );
  });

  testWidgets('o texto rola na vertical e nada escapa na horizontal',
      (tester) async {
    await _pump(tester);

    // Documento legal em celular é longo por natureza; o que não pode é
    // exigir rolagem lateral para ler uma frase.
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.vertical);
  });
}

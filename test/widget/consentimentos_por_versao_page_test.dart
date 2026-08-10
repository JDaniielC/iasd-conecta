import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/legal/domain/consent_tally.dart';
import 'package:iasd_conecta/features/legal/legal_providers.dart';
import 'package:iasd_conecta/features/legal/presentation/consent_versions_page.dart';

/// O teste de widget não fala com o banco: sobrescreve `consentTallyProvider`
/// com valores fixos e olha só o que a tela faz com eles.
Future<void> _pump(WidgetTester tester, List<ConsentTally> tallies) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consentTallyProvider.overrideWith((ref) async => tallies),
      ],
      child: const MaterialApp(home: ConsentVersionsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra a contagem de cada versão e rotula a nula', (
    tester,
  ) async {
    await _pump(tester, const [
      ConsentTally(
        kind: ConsentKind.lgpd,
        consentedVersion: '1.2',
        count: 12,
      ),
      ConsentTally(kind: ConsentKind.lgpd, consentedVersion: null, count: 5),
    ]);

    expect(find.text('Versão 1.2 — 12 pessoas'), findsOneWidget);
    // Nunca "0" e nunca célula vazia: a versão desconhecida é uma resposta,
    // não a falta de uma.
    expect(find.text('Versão desconhecida — 5 pessoas'), findsOneWidget);
  });

  testWidgets('não inventa a linha "Versão desconhecida" quando não há', (
    tester,
  ) async {
    await _pump(tester, const [
      ConsentTally(kind: ConsentKind.lgpd, consentedVersion: '1.2', count: 4),
    ]);

    expect(find.textContaining('Versão desconhecida'), findsNothing);
  });

  testWidgets('separa os dois tipos de consentimento', (tester) async {
    await _pump(tester, const [
      ConsentTally(kind: ConsentKind.lgpd, consentedVersion: '1.2', count: 4),
      ConsentTally(kind: ConsentKind.church, consentedVersion: '1.2', count: 1),
    ]);

    expect(find.text('Consentimento LGPD'), findsOneWidget);
    expect(find.text('Consentimento de Igreja de origem'), findsOneWidget);
    expect(find.text('Versão 1.2 — 1 pessoa'), findsOneWidget);
  });
}

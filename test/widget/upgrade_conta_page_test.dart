import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/features/perfil/presentation/upgrade_conta_page.dart';

void main() {
  testWidgets(
    'FR-011: upgrade pode ser cancelado sem bloquear navegação',
    (tester) async {
      var voltouCom = 'nao-navegou';

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    final resultado = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const UpgradeContaPage()),
                    );
                    voltouCom = 'voltou:$resultado';
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Virar Conta'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(voltouCom, 'voltou:false');
      expect(find.text('Virar Conta'), findsNothing);
    },
  );
}

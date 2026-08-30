import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/features/navigation/presentation/app_bottom_nav.dart';

Future<void> _pump(WidgetTester tester, {required AppTab current}) async {
  final router = GoRouter(
    initialLocation: '/grupos',
    routes: [
      for (final path in ['/meus-grupos', '/grupos', '/acoes', '/notificacoes'])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(
            body: Text('TELA_$path'),
            bottomNavigationBar: AppBottomNav(current: current),
          ),
        ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra as quatro paradas, com "Notificações" no lugar de Novidades',
      (tester) async {
    await _pump(tester, current: AppTab.groups);

    expect(find.text('Meus Grupos'), findsOneWidget);
    expect(find.text('Grupos'), findsOneWidget);
    expect(find.text('Ações'), findsOneWidget);
    expect(find.text('Notificações'), findsOneWidget);
    expect(find.text('Novidades'), findsNothing);
  });

  testWidgets('tocar numa aba navega pra rota dela (go, não empilha)',
      (tester) async {
    await _pump(tester, current: AppTab.groups);

    await tester.tap(find.text('Ações'));
    await tester.pumpAndSettle();

    expect(find.text('TELA_/acoes'), findsOneWidget);
    // `go` substitui a rota — a tela de Grupos não fica embaixo na pilha.
    expect(find.text('TELA_/grupos'), findsNothing);
  });
}

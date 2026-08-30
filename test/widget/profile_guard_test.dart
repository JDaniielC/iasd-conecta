import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/profile/domain/profile_guard.dart';

/// Change `afirmar-sem-conferir` — PENDENCIAS § 2.31.
///
/// `ProfileGuard` decidia com `ref.read(hasProfileProvider).value ?? false`. Um
/// `FutureProvider` que ninguém leu antes nasce `AsyncLoading`, `.value` é
/// `null`, e o guard respondia **"não tem Perfil"** sobre uma pergunta que
/// ainda não tinha resposta.
///
/// Em produção não quebrava por um motivo que não estava escrito no
/// `ProfileGuard`: `lib/app.dart:47` faz `ref.listen(hasProfileProvider, ...)`
/// no arranque do router, e o provider não é `autoDispose`. A corretude do
/// guard morava numa linha de outro arquivo, que ninguém que edite o router tem
/// motivo para preservar.
///
/// **Este arquivo exercita o guard SOZINHO**, sem nenhuma outra parte do app
/// ter lido o provider antes. É o estado que decidia errado.

/// Tela mínima: só o botão que aciona o guard. Nada mais monta, nada mais lê
/// `hasProfileProvider` — que é o ponto.
class _GateProbe extends ConsumerWidget {
  const _GateProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            if (!await ProfileGuard.requireProfile(context, ref)) return;
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('A ação seguiu.')),
            );
          },
          child: const Text('Agir'),
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, {required bool hasProfile}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _GateProbe()),
      GoRoute(path: '/cadastro', builder: (_, _) => const Text('tela de cadastro')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // `async`, de propósito: é o que reproduz o provider ainda não
        // resolvido no instante do toque. Um override síncrono esconderia
        // exatamente o defeito que este arquivo existe para pegar.
        hasProfileProvider.overrideWith((ref) async => hasProfile),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quem TEM Perfil segue, mesmo sem ninguém ter lido o provider antes',
      (tester) async {
    await _pump(tester, hasProfile: true);

    await tester.tap(find.text('Agir'));
    await tester.pumpAndSettle();

    expect(find.text('A ação seguiu.'), findsOneWidget);
    expect(find.text('tela de cadastro'), findsNothing);
  });

  testWidgets('quem NÃO tem Perfil vai para o cadastro', (tester) async {
    await _pump(tester, hasProfile: false);

    await tester.tap(find.text('Agir'));
    await tester.pumpAndSettle();

    expect(find.text('tela de cadastro'), findsOneWidget);
    expect(find.text('A ação seguiu.'), findsNothing);
  });
}

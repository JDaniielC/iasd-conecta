import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/theme/app_theme.dart';

/// Placeholder — telas de Grupo/Ação chegam em features futuras.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final temConta = ref.watch(authRepositoryProvider).temConta;

    return Scaffold(
      appBar: AppBar(title: const Text('Início')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bem-vindo!', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Grupos e Ações chegam nas próximas features. Por enquanto, '
              'você já tem um Perfil ativo neste aparelho.',
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!temConta)
              OutlinedButton(
                onPressed: () => context.push('/upgrade-conta'),
                child: const Text('Virar Conta (persistir em outro aparelho)'),
              ),
          ],
        ),
      ),
    );
  }
}

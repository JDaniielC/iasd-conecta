import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';

/// CTA reusado em listas públicas (Grupos, Ações) pra quem ainda não tem
/// Perfil — navegação é sempre livre (FR-005/FR-008/FR-010), isto é só o
/// ponto de entrada manual pro cadastro.
class PerfilAusenteBanner extends ConsumerWidget {
  const PerfilAusenteBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPerfil = ref.watch(hasPerfilProvider).value ?? false;
    if (hasPerfil) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Expanded(child: Text('Crie um Perfil pra participar.')),
          TextButton(
            onPressed: () => context.push('/cadastro'),
            child: const Text('Criar Perfil'),
          ),
        ],
      ),
    );
  }
}

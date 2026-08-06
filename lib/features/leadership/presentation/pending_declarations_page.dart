import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../grupo/grupo_providers.dart';
import '../domain/leadership_declaration.dart';
import '../leadership_providers.dart';

/// Fila de declarações pendentes de todo o distrito, só pro Administrador
/// (User Story 2) — FR-004/FR-005: nunca o Dono do Grupo decide.
class PendingDeclarationsPage extends ConsumerWidget {
  const PendingDeclarationsPage({super.key});

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    String declarationId,
    bool approve,
  ) async {
    try {
      await ref.read(leadershipRepositoryProvider).decide(
            declarationId: declarationId,
            approve: approve,
          );
      ref.invalidate(pendingDeclarationsProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra decidir agora. Tente de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingDeclarationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Declarações pendentes')),
      body: pendingAsync.when(
        data: (declarations) {
          if (declarations.isEmpty) {
            return const Center(child: Text('Nenhuma declaração pendente.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: declarations.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final declaration = declarations[index];
              return _PendingCard(
                declaration: declaration,
                onApprove: () => _decide(context, ref, declaration.id, true),
                onReject: () => _decide(context, ref, declaration.id, false),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Não deu pra carregar as pendências.')),
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({
    required this.declaration,
    required this.onApprove,
    required this.onReject,
  });

  final LeadershipDeclaration declaration;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupoAsync = ref.watch(grupoProvider(declaration.groupId));
    final declaranteAsync = ref.watch(perfilPublicoProvider(declaration.userId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              grupoAsync.value?.nome ?? 'Grupo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Declarante: ${declaranteAsync.value?.displayName ?? '...'}'),
            Text('Ano: ${declaration.year}'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                ElevatedButton(onPressed: onApprove, child: const Text('Confirmar')),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(onPressed: onReject, child: const Text('Rejeitar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

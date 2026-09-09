import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../action_providers.dart';
import '../domain/attendance.dart';

/// A seção de comparecimento na tela da Ação.
///
/// A REGRA QUE ESTA TELA TRADUZ, e que é fácil de traduzir errado: enquanto a
/// lista está aberta, quem não foi marcado está **não registrado**, e não
/// ausente. Uma lista de nomes com caixa desmarcada é lida por qualquer pessoa
/// como "faltou" — por isso cada linha carrega a palavra, e a palavra muda
/// quando a lista fecha.
class AttendanceSection extends ConsumerWidget {
  const AttendanceSection({
    super.key,
    required this.actionId,
    required this.isCreator,
  });

  final String actionId;

  /// Só quem criou a Ação marca e fecha. A tela esconde; a policy e o gatilho
  /// é que garantem.
  final bool isCreator;

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AttendanceMark mark,
  ) async {
    final repository = ref.read(attendanceRepositoryProvider);
    try {
      if (mark.isMarked) {
        await repository.unmarkAttendance(
          actionId: actionId,
          userId: mark.profile.id,
        );
      } else {
        await repository.markAttendance(
          actionId: actionId,
          userId: mark.profile.id,
        );
      }
      ref.invalidate(attendanceListProvider(actionId));
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fechar a lista?'),
        // O aviso não é formalidade: fechar é o ato que transforma quem não foi
        // marcado em ausente, e ele não se desfaz.
        content: const Text(
          'Depois de fechar, quem não estiver marcado passa a constar como '
          'ausente, e a lista não reabre. Quem discordar poderá contestar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fechar lista'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(attendanceRepositoryProvider).closeList(actionId);
      ref.invalidate(attendanceListProvider(actionId));
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    PendingDispute dispute,
    String decision,
  ) async {
    try {
      await ref.read(attendanceRepositoryProvider).decideDispute(
            actionId: dispute.actionId,
            userId: dispute.profile.id,
            decision: decision,
          );
      ref.invalidate(pendingDisputesProvider(actionId));
      ref.invalidate(attendanceListProvider(actionId));
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(attendanceListProvider(actionId));

    return listAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.marks.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quem esteve',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (list.isClosed)
                // A contagem CONGELADA, não a atual. Recalcular faria o
                // histórico mudar quando alguém excluísse a conta.
                Text(
                  'Lista fechada em '
                  '${DateFormat('dd/MM/yyyy').format(list.closedAt!)}. '
                  'Estiveram presentes: ${list.presentAtClosing ?? 0}.',
                )
              else
                const Text(
                  'A lista está aberta. Enquanto ela não for fechada, quem '
                  'não estiver marcado consta como não registrado — nunca '
                  'como ausente.',
                ),
              const SizedBox(height: AppSpacing.sm),
              for (final mark in list.marks)
                _MarkTile(
                  mark: mark,
                  closed: list.isClosed,
                  canEdit: isCreator && !list.isClosed,
                  onToggle: () => _toggle(context, ref, mark),
                ),
              if (isCreator && !list.isClosed) ...[
                const SizedBox(height: AppSpacing.sm),
                FilledButton(
                  onPressed: () => _close(context, ref),
                  child: const Text('Fechar lista'),
                ),
              ],
              if (isCreator) _DisputeDecisions(actionId: actionId, onDecide: (
                dispute,
                decision,
              ) => _decide(context, ref, dispute, decision)),
            ],
          ),
        );
      },
    );
  }
}

class _MarkTile extends StatelessWidget {
  const _MarkTile({
    required this.mark,
    required this.closed,
    required this.canEdit,
    required this.onToggle,
  });

  final AttendanceMark mark;
  final bool closed;
  final bool canEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    // AS TRÊS PALAVRAS, e a do meio é a que a change existe para preservar.
    final String status;
    if (mark.isMarked) {
      status = 'Presente';
    } else if (closed) {
      status = 'Ausente';
    } else {
      status = 'Não registrado';
    }

    final subtitle = mark.disputed
        ? '$status · Contestada — não conta em nenhum número'
        : status;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(mark.profile.displayName),
      subtitle: Text(subtitle),
      trailing: canEdit
          ? Checkbox(value: mark.isMarked, onChanged: (_) => onToggle())
          : null,
    );
  }
}

class _DisputeDecisions extends ConsumerWidget {
  const _DisputeDecisions({required this.actionId, required this.onDecide});

  final String actionId;
  final void Function(PendingDispute dispute, String decision) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputes = ref.watch(pendingDisputesProvider(actionId)).value;
    if (disputes == null || disputes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          'Contestações a decidir',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        // Quem decide precisa saber disto ANTES de decidir, senão vai ler
        // "Manter" como "volta a contar" — e não volta.
        const Text(
          'Decida o que aconteceu de fato. De qualquer forma, a marca '
          'contestada não volta a contar em nenhum número.',
        ),
        for (final dispute in disputes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(dispute.profile.displayName),
            subtitle: Text(
              'Contestou em '
              '${DateFormat('dd/MM/yyyy').format(dispute.disputedAt)}',
            ),
            trailing: OverflowBar(
              spacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: () => onDecide(dispute, 'desfeita'),
                  child: const Text('Desfazer'),
                ),
                TextButton(
                  onPressed: () => onDecide(dispute, 'mantida'),
                  child: const Text('Manter'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

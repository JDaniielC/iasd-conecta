import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../action/action_providers.dart';
import '../../../action/domain/attendance.dart';

/// O que afirmaram sobre mim, em "Meu Perfil".
///
/// Comparecimento é o primeiro dado do app escrito por TERCEIRO sobre o
/// titular. Esta seção é o contrapeso: cada afirmação aparece com o nome de
/// quem a fez, e pode ser contestada. Sem o nome, a pessoa saberia que alguém
/// disse algo sobre ela e não com quem falar.
class MyAttendanceSection extends ConsumerWidget {
  const MyAttendanceSection({super.key, this.onDispute});

  /// Injetável para o teste de widget não precisar de um cliente do Supabase.
  final Future<void> Function(String actionId)? onDispute;

  Future<void> _dispute(
    BuildContext context,
    WidgetRef ref,
    String actionId,
  ) async {
    try {
      if (onDispute != null) {
        await onDispute!(actionId);
      } else {
        await ref.read(attendanceRepositoryProvider).disputeAttendance(actionId);
      }
      ref.invalidate(myAttendanceProvider);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(myAttendanceProvider).value;
    // Lista vazia some inteira. "Você não tem presenças registradas" seria
    // informação sobre a ausência de informação — ruído para quem nunca foi
    // marcado, que é a maioria.
    if (records == null || records.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Presenças registradas sobre você',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'Quem organiza a Ação marca quem esteve lá. Se alguma marca estiver '
          'errada, você pode contestar.',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final record in records)
          _RecordTile(
            record: record,
            onDispute: () => _dispute(context, ref, record.actionId),
          ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onDispute});

  final MyAttendanceRecord record;
  final VoidCallback onDispute;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy');
    final dispute = record.dispute;

    final String status;
    if (dispute == null) {
      status = 'Marcada por ${record.markedByName} em '
          '${date.format(record.attendedAt)}';
    } else if (dispute.isPending) {
      status = 'Contestada em ${date.format(dispute.disputedAt)}, aguardando '
          'a decisão de quem organizou. Já não conta em nenhum número.';
    } else if (dispute.decision == 'desfeita') {
      status = 'Contestada, e a marca foi desfeita. Não conta em nenhum '
          'número.';
    } else {
      // O caso que dá sentido ao resto: mesmo mantida, a linha não volta.
      // Dizer só "mantida" faria a pessoa concluir que perdeu.
      status = 'Contestada, e quem organizou manteve a marca. Ela não conta '
          'em nenhum número mesmo assim.';
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      // Sem a data quando a Ação não é mais legível: inventar uma seria pior
      // do que omiti-la, e a marca continua contestável sem ela.
      title: Text(
        record.actionDate == null
            ? record.actionName
            : '${record.actionName} — ${date.format(record.actionDate!)}',
      ),
      subtitle: Text(status),
      trailing: record.canDispute
          ? TextButton(onPressed: onDispute, child: const Text('Contestar'))
          : null,
    );
  }
}

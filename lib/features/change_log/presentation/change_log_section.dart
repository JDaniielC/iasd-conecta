import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../change_log_providers.dart';
import '../data/change_log_repository.dart';
import '../domain/change_log_entry.dart';

/// Seção "Mudanças recentes", usada no detalhe do Grupo e no da Ação.
///
/// Widget próprio, numa feature própria, porque o mesmo modelo e o mesmo
/// repositório servem as duas telas — duas cópias divergem. Nenhum contrato dos
/// widgets existentes muda: as duas telas só consomem esta.
class ChangeLogSection extends ConsumerWidget {
  const ChangeLogSection.forGroup({super.key, required this.groupId})
      : actionId = null;

  const ChangeLogSection.forAction({super.key, required this.actionId})
      : groupId = null;

  /// Exatamente um dos dois é não nulo — os construtores nomeados garantem.
  final String? groupId;
  final String? actionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = groupId != null
        ? ref.watch(groupChangeLogProvider(groupId!))
        : ref.watch(actionChangeLogProvider(actionId!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mudanças recentes',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
          error: (_, _) => const Text('Não deu pra carregar as mudanças.'),
          data: (todas) {
            if (todas.isEmpty) return const _RegistroVazio();
            // Veio o item extra? Então há mais do que cabe aqui.
            final haMais = todas.length > ChangeLogRepository.pageSize;
            final visiveis =
                todas.take(ChangeLogRepository.pageSize).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in visiveis) _Linha(entrada: e),
                if (haMais) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Há mudanças mais antigas que não aparecem aqui.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.entrada});

  final ChangeLogEntry entrada;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(entrada.sentence)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            DateFormat('dd/MM HH:mm').format(entrada.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Registro vazio não é erro nem carregamento — é o estado normal de tudo que
/// existia antes desta funcionalidade. Sem este texto, a seção vazia lê como
/// bug.
class _RegistroVazio extends StatelessWidget {
  const _RegistroVazio();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Nada mudou por aqui ainda. O registro começa agora — o que aconteceu '
      'antes não foi guardado.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

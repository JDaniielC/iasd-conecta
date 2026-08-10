import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/group.dart';
import '../group_providers.dart';

/// Grupos arquivados — só o Administrador do distrito (FR-019).
///
/// É a tela de consertar engano. Mostra **quem arquivou e quando**, porque é
/// isso que permite decidir se desarquiva: um Dono que arquivou o próprio Grupo
/// por engano ontem é caso diferente de um Grupo arquivado pelo Administrador
/// há seis meses.
class ArchivedGroupsPage extends ConsumerWidget {
  const ArchivedGroupsPage({super.key});

  static String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  Future<void> _unarchive(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desarquivar este Grupo/Ministério?'),
        // FR-022: a segunda metade da honestidade que a confirmação de
        // arquivar começou. Desarquivar devolve o Grupo e os participantes, e
        // só isso — prometer mais seria mentir na direção contrária.
        content: const Text(
          'Ele volta à lista e os participantes voltam junto.\n\n'
          'As Ações que foram canceladas NÃO voltam, e as Rodadas de votação '
          'encerradas continuam encerradas — as Ações candidatas delas já '
          'foram descartadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Desistir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desarquivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(groupRepositoryProvider).unarchiveGroup(group.id);
      ref.invalidate(archivedGroupsProvider);
      ref.invalidate(groupsProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra desarquivar agora.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(archivedGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Grupos/Ministérios arquivados')),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não deu pra carregar agora.'),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text('Nenhum Grupo/Ministério arquivado.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              for (final group in groups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(group.name),
                  subtitle: Text(
                    'Arquivado em ${_formatDate(group.archivedAt)}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: () => _unarchive(context, ref, group),
                    child: const Text('Desarquivar'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

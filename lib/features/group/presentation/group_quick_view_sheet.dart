import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/domain/profile.dart';
import '../../profile/domain/profile_guard.dart';
import '../domain/group.dart';
import '../group_providers.dart';

/// Pré-visualização de um Grupo antes de abrir a tela cheia — o toque no
/// cartão da lista abre isto, e só "Ver detalhes" leva pra
/// [GroupDetailPage]. Participar/Sair já acontece aqui, sem precisar
/// navegar: é a decisão mais comum de quem só queria confirmar horário e
/// local.
class GroupQuickViewSheet extends ConsumerWidget {
  const GroupQuickViewSheet({super.key, required this.group});

  final Group group;

  static Future<void> show(BuildContext context, Group group) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupQuickViewSheet(group: group),
    );
  }

  Future<void> _toggleParticipation(
    BuildContext context,
    WidgetRef ref, {
    required bool isParticipant,
  }) async {
    if (!isParticipant && !await ProfileGuard.requireProfile(context, ref)) {
      return;
    }
    try {
      final repository = ref.read(groupRepositoryProvider);
      if (isParticipant) {
        await repository.leave(group.id);
      } else {
        await repository.join(group.id);
      }
      ref.invalidate(membersProvider(group.id));
      ref.invalidate(myGroupIdsProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isParticipant
                ? 'Não deu pra sair do Grupo. Se você é o Dono, transfira a posse antes.'
                : 'Não deu pra participar agora. Tente de novo.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider(group.id));
    final members = membersAsync.value ?? const [];
    final uid = ref.watch(currentUserIdProvider);
    final isParticipant = members.any((p) => p.id == uid);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _CategoryChip(label: group.category)),
                IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(group.name, style: Theme.of(context).textTheme.headlineSmall),
            if (group.details != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(group.details!),
            ],
            const SizedBox(height: AppSpacing.md),
            if (group.schedule != null)
              _InfoRow(icon: Icons.schedule_outlined, text: group.schedule!),
            if (group.location != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _InfoRow(icon: Icons.location_on_outlined, text: group.location!),
            ],
            const SizedBox(height: AppSpacing.md),
            _MemberAvatars(members: members),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/grupos/${group.id}');
                    },
                    child: const Text('Ver detalhes'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    style: isParticipant
                        ? OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          )
                        : null,
                    onPressed: () => _toggleParticipation(
                      context,
                      ref,
                      isParticipant: isParticipant,
                    ),
                    child: Text(isParticipant ? 'Sair' : 'Participar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text)),
      ],
    );
  }
}

/// Avatares por iniciais — o Perfil não tem foto (ver `perfis`, sem coluna de
/// imagem). Só os cinco primeiros aparecem; o resto vira "+N".
class _MemberAvatars extends StatelessWidget {
  const _MemberAvatars({required this.members});

  final List<PublicProfile> members;

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    final shown = members.take(_maxShown).toList();
    final overflow = members.length - shown.length;

    // Largura explícita, e não só altura: um Stack só com filhos Positioned
    // não tem como calcular o próprio tamanho e exige as duas dimensões
    // limitadas — dentro de um Row sem Expanded a largura vem infinita e o
    // layout estoura (achado por group_quick_view_sheet_test.dart).
    final stackWidth = (shown.length - 1) * 28.0 + 36;
    return Row(
      children: [
        SizedBox(
          height: 36,
          width: stackWidth,
          child: Stack(
            children: [
              for (final (i, member) in shown.indexed)
                Positioned(
                  left: i * 28.0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        Colors.primaries[member.id.hashCode % Colors.primaries.length],
                    child: Text(
                      member.displayName.isEmpty
                          ? '?'
                          : member.displayName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            overflow > 0
                ? '+$overflow membros inscritos no Grupo'
                : 'membros inscritos no Grupo',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

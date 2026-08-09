import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../leadership/leadership_providers.dart';
import '../../profile/domain/profile_guard.dart';
import '../group_providers.dart';

/// Detalhes de um Grupo: visível a Visitante e Usuário igualmente
/// (FR-005). Participar/sair exige Perfil (FR-006/FR-007/FR-008/FR-009).
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  void _mostrarErro(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _participar(BuildContext context, WidgetRef ref) async {
    if (!ProfileGuard.requireProfile(context, ref)) return;
    try {
      await ref.read(groupRepositoryProvider).join(groupId);
      ref.invalidate(membersProvider(groupId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra participar agora. Tente de novo.');
    }
  }

  Future<void> _sair(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupRepositoryProvider).leave(groupId);
      ref.invalidate(membersProvider(groupId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(
        context,
        'Não deu pra sair do Grupo. Se você é o Dono, transfira a posse antes.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupoAsync = ref.watch(groupProvider(groupId));
    final participantesAsync = ref.watch(membersProvider(groupId));
    final uid = ref.watch(currentUserIdProvider);
    final participa = participantesAsync.value?.any((p) => p.id == uid) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Grupo')),
      body: grupoAsync.when(
        data: (grupo) {
          final isOwner = grupo.isOwner(uid);
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(grupo.name, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.how_to_vote_outlined),
                      tooltip: 'Rodadas de Votação',
                      onPressed: () => context.push('/grupos/$groupId/rodadas'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.badge_outlined),
                      tooltip: 'Líder/Diretor de Ministério',
                      onPressed: () => context.push('/grupos/$groupId/leadership/declare'),
                    ),
                    if (isOwner)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => context.push('/grupos/$groupId/editar'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(grupo.category),
                if (grupo.schedule != null || grupo.local != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  if (grupo.schedule != null) Text('Horário: ${grupo.schedule}'),
                  if (grupo.local != null) Text('Local: ${grupo.local}'),
                ],
                if (grupo.details != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(grupo.details!),
                ],
                const SizedBox(height: AppSpacing.md),
                _LeadersSection(groupId: groupId),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: participa ? () => _sair(context, ref) : () => _participar(context, ref),
                  child: Text(participa ? 'Sair do Grupo' : 'Participar'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: participantesAsync.when(
                    data: (members) => ListView(
                      children: members
                          .map((p) => ListTile(title: Text(p.displayName)))
                          .toList(),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Não deu pra carregar os participantes.'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Grupo não encontrado.')),
      ),
    );
  }
}

/// FR-006/FR-007: identificação pública do(s) Líder(es)/Diretor(es)
/// confirmado(s) do ano corrente — visível até pra Visitante sem cadastro.
/// Sem confirmado nenhum, a seção não aparece (Grupo comum, não Ministério).
class _LeadersSection extends ConsumerWidget {
  const _LeadersSection({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadersAsync = ref.watch(currentLeadersProvider(groupId));
    final leaders = leadersAsync.value ?? const [];
    if (leaders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Líder/Diretor', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ...leaders.map((leader) => _LeaderName(userId: leader.userId)),
      ],
    );
  }
}

class _LeaderName extends ConsumerWidget {
  const _LeaderName({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfilAsync = ref.watch(publicProfileProvider(userId));
    return Text(perfilAsync.value?.displayName ?? '...');
  }
}

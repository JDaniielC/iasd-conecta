import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../leadership/leadership_providers.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../grupo_providers.dart';

/// Detalhes de um Grupo: visível a Visitante e Usuário igualmente
/// (FR-005). Participar/sair exige Perfil (FR-006/FR-007/FR-008/FR-009).
class DetalheGrupoPage extends ConsumerWidget {
  const DetalheGrupoPage({super.key, required this.grupoId});

  final String grupoId;

  void _mostrarErro(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _participar(BuildContext context, WidgetRef ref) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    try {
      await ref.read(grupoRepositoryProvider).participar(grupoId);
      ref.invalidate(participantesProvider(grupoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra participar agora. Tente de novo.');
    }
  }

  Future<void> _sair(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(grupoRepositoryProvider).sair(grupoId);
      ref.invalidate(participantesProvider(grupoId));
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
    final grupoAsync = ref.watch(grupoProvider(grupoId));
    final participantesAsync = ref.watch(participantesProvider(grupoId));
    final uid = ref.watch(currentUserIdProvider);
    final participa = participantesAsync.valueOrNull?.any((p) => p.id == uid) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Grupo')),
      body: grupoAsync.when(
        data: (grupo) {
          final souDono = grupo.souDono(uid);
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(grupo.nome, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.how_to_vote_outlined),
                      tooltip: 'Rodadas de Votação',
                      onPressed: () => context.push('/grupos/$grupoId/rodadas'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.badge_outlined),
                      tooltip: 'Líder/Diretor de Ministério',
                      onPressed: () => context.push('/grupos/$grupoId/leadership/declare'),
                    ),
                    if (souDono)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => context.push('/grupos/$grupoId/editar'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(grupo.categoria),
                const SizedBox(height: AppSpacing.md),
                Text('Horário: ${grupo.horario}'),
                Text('Local: ${grupo.local}'),
                if (grupo.detalhes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(grupo.detalhes!),
                ],
                const SizedBox(height: AppSpacing.md),
                _LeadersSection(grupoId: grupoId),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: participa ? () => _sair(context, ref) : () => _participar(context, ref),
                  child: Text(participa ? 'Sair do Grupo' : 'Participar'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: participantesAsync.when(
                    data: (participantes) => ListView(
                      children: participantes
                          .map((p) => ListTile(title: Text(p.nomeExibido)))
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
  const _LeadersSection({required this.grupoId});

  final String grupoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadersAsync = ref.watch(currentLeadersProvider(grupoId));
    final leaders = leadersAsync.valueOrNull ?? const [];
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
    final perfilAsync = ref.watch(perfilPublicoProvider(userId));
    return Text(perfilAsync.valueOrNull?.nomeExibido ?? '...');
  }
}

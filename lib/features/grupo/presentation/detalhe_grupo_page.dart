import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../grupo_providers.dart';

/// Detalhes de um Grupo: visível a Visitante e Usuário igualmente
/// (FR-005). Participar/sair exige Perfil (FR-006/FR-007/FR-008/FR-009).
class DetalheGrupoPage extends ConsumerWidget {
  const DetalheGrupoPage({super.key, required this.grupoId});

  final String grupoId;

  Future<void> _participar(BuildContext context, WidgetRef ref) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    await ref.read(grupoRepositoryProvider).participar(grupoId);
    ref.invalidate(participantesProvider(grupoId));
  }

  Future<void> _sair(WidgetRef ref) async {
    await ref.read(grupoRepositoryProvider).sair(grupoId);
    ref.invalidate(participantesProvider(grupoId));
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
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  onPressed: participa ? () => _sair(ref) : () => _participar(context, ref),
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

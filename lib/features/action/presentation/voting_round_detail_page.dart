import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../voting_round_providers.dart';

/// Detalhes de uma Rodada de votação: candidatas + votar (User Story 2) +
/// encerrar antes do prazo, só Dono do Grupo (User Story 3).
class VotingRoundDetailPage extends ConsumerWidget {
  const VotingRoundDetailPage({super.key, required this.votingRoundId});

  final String votingRoundId;

  void _mostrarErro(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _votar(BuildContext context, WidgetRef ref, String candidataId) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    try {
      await ref.read(votingRoundRepositoryProvider).vote(votingRoundId, candidataId);
      ref.invalidate(myVoteProvider(votingRoundId));
      ref.invalidate(candidatesProvider(votingRoundId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra votar agora. A Rodada ainda está aberta?');
    }
  }

  Future<void> _encerrar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(votingRoundRepositoryProvider).closeIfDue(votingRoundId, forcar: true);
      ref.invalidate(votingRoundProvider(votingRoundId));
      ref.invalidate(candidatesProvider(votingRoundId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra encerrar agora. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rodadaAsync = ref.watch(votingRoundProvider(votingRoundId));
    final candidatasAsync = ref.watch(candidatesProvider(votingRoundId));
    final meuVotoAsync = ref.watch(myVoteProvider(votingRoundId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rodada de Votação')),
      body: rodadaAsync.when(
        data: (rodada) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rodada.aberta ? 'Aberta' : 'Fechada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('Prazo: ${DateFormat('dd/MM/yyyy HH:mm').format(rodada.deadline)}'),
                if (rodada.aberta) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (PerfilGuard.exigirPerfil(context, ref)) {
                            context.push('/rodadas/$votingRoundId/candidatas/novo');
                          }
                        },
                        child: const Text('Propor Candidata'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: () => _encerrar(context, ref),
                        child: const Text('Encerrar Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text('Candidatas', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: candidatasAsync.when(
                    data: (candidatas) {
                      final myVote = meuVotoAsync.value;
                      if (candidatas.isEmpty) {
                        return const Center(child: Text('Nenhuma candidata ainda.'));
                      }
                      return ListView.builder(
                        itemCount: candidatas.length,
                        itemBuilder: (context, index) {
                          final candidata = candidatas[index];
                          final votadaPorMim = myVote?.candidataId == candidata.id;
                          return Card(
                            child: ListTile(
                              title: Text(candidata.nome),
                              subtitle: Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(candidata.dateTime)} · ${candidata.local}',
                              ),
                              onTap: () => context.push('/acoes/${candidata.id}'),
                              trailing: rodada.aberta
                                  ? OutlinedButton(
                                      onPressed: votadaPorMim
                                          ? null
                                          : () => _votar(context, ref, candidata.id),
                                      child: Text(votadaPorMim ? 'Seu voto' : 'Votar'),
                                    )
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Não deu pra carregar as candidatas.'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Rodada não encontrada.')),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/domain/profile_guard.dart';
import '../voting_round_providers.dart';

/// Detalhes de uma Rodada de votação: candidatas + votar (User Story 2) +
/// encerrar antes do prazo, só Dono do Grupo (User Story 3).
class VotingRoundDetailPage extends ConsumerWidget {
  const VotingRoundDetailPage({super.key, required this.votingRoundId});

  final String votingRoundId;

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _vote(BuildContext context, WidgetRef ref, String candidateId) async {
    if (!ProfileGuard.requireProfile(context, ref)) return;
    try {
      await ref.read(votingRoundRepositoryProvider).vote(votingRoundId, candidateId);
      ref.invalidate(myVoteProvider(votingRoundId));
      ref.invalidate(candidatesProvider(votingRoundId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra votar agora. A Rodada ainda está aberta?');
    }
  }

  Future<void> _encerrar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(votingRoundRepositoryProvider).closeIfDue(votingRoundId, forcar: true);
      ref.invalidate(votingRoundProvider(votingRoundId));
      ref.invalidate(candidatesProvider(votingRoundId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra encerrar agora. Tente de novo.');
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
        data: (votingRound) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  votingRound.isOpen ? 'Aberta' : 'Fechada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('Prazo: ${DateFormat('dd/MM/yyyy HH:mm').format(votingRound.deadline)}'),
                if (votingRound.isOpen) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (ProfileGuard.requireProfile(context, ref)) {
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
                    data: (candidates) {
                      final myVote = meuVotoAsync.value;
                      if (candidates.isEmpty) {
                        return const Center(child: Text('Nenhuma candidata ainda.'));
                      }
                      return ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final votadaPorMim = myVote?.candidateId == candidate.id;
                          return Card(
                            child: ListTile(
                              title: Text(candidate.name),
                              subtitle: Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(candidate.dateTime)} · ${candidate.local}',
                              ),
                              onTap: () => context.push('/acoes/${candidate.id}'),
                              trailing: votingRound.isOpen
                                  ? OutlinedButton(
                                      onPressed: votadaPorMim
                                          ? null
                                          : () => _vote(context, ref, candidate.id),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../profile/domain/profile_guard.dart';
import '../voting_round_providers.dart';
import '../../notification/presentation/notification_badge.dart';

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

  Future<void> _close(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(votingRoundRepositoryProvider).closeIfDue(votingRoundId, force: true);
      ref.invalidate(votingRoundProvider(votingRoundId));
      ref.invalidate(candidatesProvider(votingRoundId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra encerrar agora. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votingRoundAsync = ref.watch(votingRoundProvider(votingRoundId));
    final candidatesAsync = ref.watch(candidatesProvider(votingRoundId));
    final myVoteAsync = ref.watch(myVoteProvider(votingRoundId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rodada de Votação'),
        // Change `notificacoes-in-app`. O app não tem barra global, então o
        // indicador entra nas telas onde a pessoa LÊ — nunca nos
        // formulários, onde ele seria distração no meio de um fluxo.
        actions: const [NotificationBadge()],
      ),
      body: votingRoundAsync.when(
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
                  // `Wrap`, não `Row`: os dois rótulos lado a lado pedem ~570px
                  // e estouravam 229px numa tela de 360 — quebrado em qualquer
                  // celular, não só nos estreitos. Achado pelo teste de widget
                  // desta tela, escrito na change `cobertura-e-tdd`.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (ProfileGuard.requireProfile(context, ref)) {
                            context.push('/rodadas/$votingRoundId/candidatas/novo');
                          }
                        },
                        child: const Text('Propor Candidata'),
                      ),
                      OutlinedButton(
                        onPressed: () => _close(context, ref),
                        child: const Text('Encerrar Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text('Candidatas', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: candidatesAsync.when(
                    data: (candidates) {
                      final myVote = myVoteAsync.value;
                      if (candidates.isEmpty) {
                        return const Center(child: Text('Nenhuma candidata ainda.'));
                      }
                      return ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final votedByMe = myVote?.candidateId == candidate.id;
                          return Card(
                            child: ListTile(
                              title: Text(candidate.name),
                              subtitle: Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(candidate.dateTime)} · ${candidate.location}',
                              ),
                              onTap: () => context.push('/acoes/${candidate.id}'),
                              trailing: votingRound.isOpen
                                  ? OutlinedButton(
                                      onPressed: votedByMe
                                          ? null
                                          : () => _vote(context, ref, candidate.id),
                                      child: Text(votedByMe ? 'Seu voto' : 'Votar'),
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

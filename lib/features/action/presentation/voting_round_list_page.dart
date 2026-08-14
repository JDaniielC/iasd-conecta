import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../profile/domain/profile_guard.dart';
import '../voting_round_providers.dart';
import '../../notification/presentation/notification_badge.dart';

/// Lista de Rodadas de votação de um Grupo — visível a Visitante e Usuário
/// igualmente (FR-017).
class VotingRoundListPage extends ConsumerWidget {
  const VotingRoundListPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votingRoundsAsync = ref.watch(groupVotingRoundsProvider(groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rodadas de Votação'),
        // Change `notificacoes-in-app`. O app não tem barra global, então o
        // indicador entra nas telas onde a pessoa LÊ — nunca nos
        // formulários, onde ele seria distração no meio de um fluxo.
        actions: const [NotificationBadge()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (ProfileGuard.requireProfile(context, ref)) {
            context.push('/grupos/$groupId/rodadas/novo');
          }
        },
        child: const Icon(Icons.add),
      ),
      body: votingRoundsAsync.when(
        data: (votingRounds) {
          if (votingRounds.isEmpty) {
            return const Center(child: Text('Nenhuma Rodada ainda.'));
          }
          return ListView.builder(
            itemCount: votingRounds.length,
            itemBuilder: (context, index) {
              final votingRound = votingRounds[index];
              return Card(
                child: ListTile(
                  title: Text(votingRound.isOpen ? 'Aberta' : 'Fechada'),
                  subtitle: Text(
                    'Prazo: ${DateFormat('dd/MM/yyyy HH:mm').format(votingRound.deadline)}',
                  ),
                  onTap: () => context.push('/rodadas/${votingRound.id}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Não deu pra carregar as Rodadas agora.')),
      ),
    );
  }
}

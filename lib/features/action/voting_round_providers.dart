import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'action_providers.dart';
import 'data/voting_round_repository.dart';
import 'domain/action.dart';
import 'domain/voting_round.dart';

final votingRoundRepositoryProvider = Provider<VotingRoundRepository>((ref) {
  return VotingRoundRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(actionRepositoryProvider),
  );
});

final groupVotingRoundsProvider =
    FutureProvider.autoDispose.family<List<VotingRound>, String>((ref, grupoId) {
  return ref.watch(votingRoundRepositoryProvider).fetchRodadasDoGrupo(grupoId);
});

final votingRoundProvider = FutureProvider.autoDispose.family<VotingRound, String>((ref, id) {
  return ref.watch(votingRoundRepositoryProvider).fetchVotingRound(id);
});

final candidatesProvider =
    FutureProvider.autoDispose.family<List<Action>, String>((ref, votingRoundId) {
  return ref.watch(votingRoundRepositoryProvider).fetchCandidatas(votingRoundId);
});

final myVoteProvider = FutureProvider.autoDispose.family<Vote?, String>((ref, votingRoundId) {
  return ref.watch(votingRoundRepositoryProvider).myVote(votingRoundId);
});

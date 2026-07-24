import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/leadership_repository.dart';
import 'domain/leadership_declaration.dart';

final leadershipRepositoryProvider = Provider<LeadershipRepository>((ref) {
  return LeadershipRepository(ref.watch(supabaseClientProvider));
});

final currentLeadersProvider = FutureProvider.autoDispose
    .family<List<LeadershipDeclaration>, String>((ref, groupId) {
  final year = DateTime.now().year;
  return ref.watch(leadershipRepositoryProvider).fetchCurrentLeaders(groupId: groupId, year: year);
});

final myDeclarationProvider = FutureProvider.autoDispose
    .family<LeadershipDeclaration?, String>((ref, groupId) {
  ref.watch(authStateChangesProvider);
  final year = DateTime.now().year;
  return ref.watch(leadershipRepositoryProvider).fetchMyDeclaration(groupId: groupId, year: year);
});

final pendingDeclarationsProvider = FutureProvider.autoDispose<List<LeadershipDeclaration>>((ref) {
  return ref.watch(leadershipRepositoryProvider).fetchPendingDeclarations();
});

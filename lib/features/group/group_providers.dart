import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../profile/domain/profile.dart';
import 'data/group_repository.dart';
import 'domain/group_category.dart';
import 'domain/group.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(supabaseClientProvider));
});

final groupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchGroups();
});

final groupCategoriesProvider = FutureProvider<List<GroupCategory>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchCategorias();
});

final groupProvider = FutureProvider.autoDispose.family<Group, String>((ref, id) {
  return ref.watch(groupRepositoryProvider).fetchGroup(id);
});

final membersProvider =
    FutureProvider.autoDispose.family<List<PublicProfile>, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchParticipantes(groupId);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../profile/domain/profile.dart';
import 'data/group_repository.dart';
import 'domain/archive_preview.dart';
import 'domain/group_category.dart';
import 'domain/group.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(supabaseClientProvider));
});

final groupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchGroups();
});

final groupCategoriesProvider = FutureProvider<List<GroupCategory>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchCategories();
});

final groupProvider = FutureProvider.autoDispose.family<Group, String>((ref, id) {
  return ref.watch(groupRepositoryProvider).fetchGroup(id);
});

/// Todos os Grupos, inclusive arquivados — só para resolver a Igreja de Ações
/// antigas. Ver `GroupRepository.fetchAllGroups`.
final allGroupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchAllGroups();
});

final archivePreviewProvider =
    FutureProvider.autoDispose.family<ArchivePreview, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchArchivePreview(groupId);
});

/// Só o Administrador do distrito tem tela para isto (FR-019).
final archivedGroupsProvider =
    FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchArchivedGroups();
});

final membersProvider =
    FutureProvider.autoDispose.family<List<PublicProfile>, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
});

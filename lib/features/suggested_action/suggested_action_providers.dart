import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../group/group_providers.dart';
import 'data/suggested_action_repository.dart';
import 'domain/suggested_action.dart';

final suggestedActionRepositoryProvider = Provider<SuggestedActionRepository>((ref) {
  return SuggestedActionRepository(ref.watch(supabaseClientProvider));
});

/// FR-004: sugestões automáticas pra uma Ação candidata, a partir da
/// Categoria do próprio Grupo — sem escolha extra de quem propõe.
final suggestionsForGroupProvider =
    FutureProvider.autoDispose.family<List<SuggestedAction>, String>((ref, groupId) async {
  final grupo = await ref.watch(grupoProvider(groupId).future);
  return ref.watch(suggestedActionRepositoryProvider).fetchByCategoryName(grupo.categoria);
});

/// FR-005: sugestões filtradas pela Categoria escolhida na tela de Ação
/// avulsa.
final suggestionsForCategoryProvider =
    FutureProvider.autoDispose.family<List<SuggestedAction>, String>((ref, categoryId) {
  return ref.watch(suggestedActionRepositoryProvider).fetchByCategoryId(categoryId);
});

final allSuggestedActionsProvider = FutureProvider.autoDispose<List<SuggestedAction>>((ref) {
  return ref.watch(suggestedActionRepositoryProvider).fetchAll();
});

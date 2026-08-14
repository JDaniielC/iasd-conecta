import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/change_log_repository.dart';
import 'domain/change_log_entry.dart';

final changeLogRepositoryProvider = Provider<ChangeLogRepository>((ref) {
  return ChangeLogRepository(ref.watch(supabaseClientProvider));
});

/// `autoDispose` porque o registro muda enquanto a tela está fora: reabrir o
/// detalhe precisa refletir o que aconteceu no meio.
final groupChangeLogProvider =
    FutureProvider.autoDispose.family<List<ChangeLogEntry>, String>(
  (ref, groupId) =>
      ref.watch(changeLogRepositoryProvider).fetchForGroup(groupId),
);

final actionChangeLogProvider =
    FutureProvider.autoDispose.family<List<ChangeLogEntry>, String>(
  (ref, actionId) =>
      ref.watch(changeLogRepositoryProvider).fetchForAction(actionId),
);

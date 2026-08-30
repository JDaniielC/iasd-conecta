import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/retention_repository.dart';
import 'domain/retention_run.dart';

final retentionRepositoryProvider = Provider<RetentionRepository>((ref) {
  return RetentionRepository(ref.watch(supabaseClientProvider));
});

/// A execução mais recente de cada faxina de retenção.
final latestRetentionRunsProvider =
    FutureProvider.autoDispose<List<RetentionRun>>((ref) {
  return ref.watch(retentionRepositoryProvider).fetchLatestRuns();
});

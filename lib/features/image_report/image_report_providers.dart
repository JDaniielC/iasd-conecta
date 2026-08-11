import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/image_report_repository.dart';
import 'domain/image_report.dart';

final imageReportRepositoryProvider = Provider<ImageReportRepository>((ref) {
  return ImageReportRepository(ref.watch(supabaseClientProvider));
});

/// As pendências do Administrador do distrito, **uma por imagem** (FR-018).
final pendingReportedImagesProvider =
    FutureProvider.autoDispose<List<ReportedImage>>((ref) {
  return ref.watch(imageReportRepositoryProvider).fetchPendingByImage();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/cover_photo_repository.dart';
import 'domain/cover_photo.dart';

final coverPhotoRepositoryProvider = Provider<CoverPhotoRepository>((ref) {
  return CoverPhotoRepository(ref.watch(supabaseClientProvider));
});

/// A capa de um Grupo, ou `null` se ele não tem. **Grupo sem capa é estado
/// normal**, não erro nem carregamento eterno (FR-002).
final groupCoverPhotoProvider =
    FutureProvider.autoDispose.family<CoverPhoto?, String>((ref, groupId) {
  return ref.watch(coverPhotoRepositoryProvider).fetchForGroup(groupId);
});

/// A capa de uma Ação, ou `null`.
final actionCoverPhotoProvider =
    FutureProvider.autoDispose.family<CoverPhoto?, String>((ref, actionId) {
  return ref.watch(coverPhotoRepositoryProvider).fetchForAction(actionId);
});

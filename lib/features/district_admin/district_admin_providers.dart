import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/district_admin_repository.dart';

final districtAdminRepositoryProvider = Provider<DistrictAdminRepository>((ref) {
  return DistrictAdminRepository(ref.watch(supabaseClientProvider));
});

/// Reavalia sempre que o estado de auth muda (ex.: upgrade pra Conta,
/// login em outro aparelho).
final isDistrictAdminProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(districtAdminRepositoryProvider).isDistrictAdmin();
});

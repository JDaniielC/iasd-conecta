import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/consent_repository.dart';
import 'domain/consent_tally.dart';

final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  return ConsentRepository(ref.watch(supabaseClientProvider));
});

/// Reavalia quando o estado de auth muda — quem é Administrador do distrito
/// pode mudar entre sessões, e a função do banco recusa quem não é.
final consentTallyProvider =
    FutureProvider.autoDispose<List<ConsentTally>>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(consentRepositoryProvider).fetchConsentTally();
});

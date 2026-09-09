import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/consent_repository.dart';
import 'domain/consent_status.dart';
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

/// Compara o aceite da pessoa com a versão vigente.
///
/// `autoDispose` de propósito: o estado muda quando ela aceita, e um provider
/// que sobrevive à tela devolveria o valor velho no próximo build — o aviso
/// continuaria aparecendo depois do aceite.
final myConsentStatusProvider =
    FutureProvider.autoDispose<ConsentStatus?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(consentRepositoryProvider).fetchMyConsentStatus();
});

/// O caminho de reaceite, isolado num provider para o teste de widget poder
/// sobrescrevê-lo sem subir um cliente do Supabase.
final acceptCurrentLegalVersionProvider =
    Provider<Future<void> Function()>((ref) {
  return ref.watch(consentRepositoryProvider).acceptCurrentVersion;
});

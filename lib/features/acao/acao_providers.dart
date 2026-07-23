import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/acao_repository.dart';
import 'domain/acao.dart';

final acaoRepositoryProvider = Provider<AcaoRepository>((ref) {
  return AcaoRepository(ref.watch(supabaseClientProvider));
});

final acoesProvider = FutureProvider.autoDispose<List<Acao>>((ref) {
  return ref.watch(acaoRepositoryProvider).fetchAcoes();
});

final acaoProvider = FutureProvider.autoDispose.family<Acao, String>((ref, id) {
  return ref.watch(acaoRepositoryProvider).fetchAcao(id);
});

final confirmadosProvider =
    FutureProvider.autoDispose.family<List<ConfirmacaoComPerfil>, String>((ref, acaoId) {
  return ref.watch(acaoRepositoryProvider).fetchConfirmados(acaoId);
});

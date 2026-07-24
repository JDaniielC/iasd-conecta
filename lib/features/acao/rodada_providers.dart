import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'acao_providers.dart';
import 'data/rodada_repository.dart';
import 'domain/acao.dart';
import 'domain/rodada.dart';

final rodadaRepositoryProvider = Provider<RodadaRepository>((ref) {
  return RodadaRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(acaoRepositoryProvider),
  );
});

final rodadasDoGrupoProvider =
    FutureProvider.autoDispose.family<List<Rodada>, String>((ref, grupoId) {
  return ref.watch(rodadaRepositoryProvider).fetchRodadasDoGrupo(grupoId);
});

final rodadaProvider = FutureProvider.autoDispose.family<Rodada, String>((ref, id) {
  return ref.watch(rodadaRepositoryProvider).fetchRodada(id);
});

final candidatasProvider =
    FutureProvider.autoDispose.family<List<Acao>, String>((ref, rodadaId) {
  return ref.watch(rodadaRepositoryProvider).fetchCandidatas(rodadaId);
});

final meuVotoProvider = FutureProvider.autoDispose.family<Voto?, String>((ref, rodadaId) {
  return ref.watch(rodadaRepositoryProvider).meuVoto(rodadaId);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../grupo/grupo_providers.dart';
import 'data/acao_repository.dart';
import 'domain/acao.dart';

final acaoRepositoryProvider = Provider<AcaoRepository>((ref) {
  return AcaoRepository(ref.watch(supabaseClientProvider));
});

final acoesProvider = FutureProvider.autoDispose<List<Acao>>((ref) {
  return ref.watch(acaoRepositoryProvider).fetchAcoes();
});

/// Resolve a Igreja de cada Ação pra permitir agrupar/filtrar a lista por
/// Igreja (`ListaAcoesPage`): Ação de Grupo herda `grupos.igreja_id`; Ação
/// avulsa usa `perfis.igreja_id` do criador, lido via RPC `perfil_publico`
/// (mesmo invariante de privacidade das outras leituras de perfil).
final acoesComIgrejaProvider = FutureProvider.autoDispose<List<AcaoComIgreja>>((ref) async {
  final acoes = await ref.watch(acoesProvider.future);
  final grupos = await ref.watch(gruposProvider.future);
  final igrejaPorGrupo = {for (final g in grupos) g.id: g.igrejaId};

  final perfilRepo = ref.watch(perfilRepositoryProvider);
  final criadoresSemGrupo =
      acoes.where((a) => a.grupoId == null).map((a) => a.criadorId).toSet();
  final perfis = await Future.wait(criadoresSemGrupo.map(perfilRepo.fetchPerfilPublico));
  final igrejaPorCriador = {for (final p in perfis) p.id: p.churchId};

  return acoes.map((acao) {
    final igrejaId =
        acao.grupoId != null ? igrejaPorGrupo[acao.grupoId] : igrejaPorCriador[acao.criadorId];
    return AcaoComIgreja(acao: acao, igrejaId: igrejaId);
  }).toList();
});

final acaoProvider = FutureProvider.autoDispose.family<Acao, String>((ref, id) {
  return ref.watch(acaoRepositoryProvider).fetchAcao(id);
});

final confirmadosProvider =
    FutureProvider.autoDispose.family<List<ConfirmacaoComPerfil>, String>((ref, acaoId) {
  return ref.watch(acaoRepositoryProvider).fetchConfirmados(acaoId);
});

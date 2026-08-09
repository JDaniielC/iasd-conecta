import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../group/group_providers.dart';
import 'data/action_repository.dart';
import 'domain/action.dart';

final actionRepositoryProvider = Provider<ActionRepository>((ref) {
  return ActionRepository(ref.watch(supabaseClientProvider));
});

final actionsProvider = FutureProvider.autoDispose<List<Action>>((ref) {
  return ref.watch(actionRepositoryProvider).fetchActions();
});

/// Resolve a Igreja de cada Ação pra permitir agrupar/filtrar a lista por
/// Igreja (`ListaAcoesPage`): Ação de Grupo herda `grupos.igreja_id`; Ação
/// avulsa usa `perfis.igreja_id` do criador, lido via RPC `perfil_publico`
/// (mesmo invariante de privacidade das outras leituras de perfil).
final actionsWithChurchProvider = FutureProvider.autoDispose<List<ActionWithChurch>>((ref) async {
  final acoes = await ref.watch(actionsProvider.future);
  final grupos = await ref.watch(groupsProvider.future);
  final igrejaPorGrupo = {for (final g in grupos) g.id: g.churchId};

  final perfilRepo = ref.watch(profileRepositoryProvider);
  final criadoresSemGrupo =
      acoes.where((a) => a.groupId == null).map((a) => a.creatorId).toSet();
  final perfis = await Future.wait(criadoresSemGrupo.map(perfilRepo.fetchPublicProfile));
  final igrejaPorCriador = {for (final p in perfis) p.id: p.churchId};

  return acoes.map((acao) {
    final churchId =
        acao.groupId != null ? igrejaPorGrupo[acao.groupId] : igrejaPorCriador[acao.creatorId];
    return ActionWithChurch(acao: acao, churchId: churchId);
  }).toList();
});

final actionProvider = FutureProvider.autoDispose.family<Action, String>((ref, id) {
  return ref.watch(actionRepositoryProvider).fetchAction(id);
});

final attendeesProvider =
    FutureProvider.autoDispose.family<List<AttendanceWithProfile>, String>((ref, acaoId) {
  return ref.watch(actionRepositoryProvider).fetchAttendees(acaoId);
});

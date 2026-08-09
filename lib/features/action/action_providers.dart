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
  final actions = await ref.watch(actionsProvider.future);
  final groups = await ref.watch(groupsProvider.future);
  final igrejaPorGrupo = {for (final g in groups) g.id: g.churchId};

  final perfilRepo = ref.watch(profileRepositoryProvider);
  final criadoresSemGrupo =
      actions.where((a) => a.groupId == null).map((a) => a.creatorId).toSet();
  final profiles = await Future.wait(criadoresSemGrupo.map(perfilRepo.fetchPublicProfile));
  final igrejaPorCriador = {for (final p in profiles) p.id: p.churchId};

  return actions.map((action) {
    final churchId =
        action.groupId != null ? igrejaPorGrupo[action.groupId] : igrejaPorCriador[action.creatorId];
    return ActionWithChurch(action: action, churchId: churchId);
  }).toList();
});

final actionProvider = FutureProvider.autoDispose.family<Action, String>((ref, id) {
  return ref.watch(actionRepositoryProvider).fetchAction(id);
});

final attendeesProvider =
    FutureProvider.autoDispose.family<List<AttendanceWithProfile>, String>((ref, acaoId) {
  return ref.watch(actionRepositoryProvider).fetchAttendees(acaoId);
});

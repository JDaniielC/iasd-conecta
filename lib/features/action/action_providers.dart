import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../group/group_providers.dart';
import 'data/action_repository.dart';
import 'data/actions_seen_repository.dart';
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
  // `allGroupsProvider`, não `groupsProvider`: este último esconde Grupo
  // arquivado (feature 014), e uma Ação passada de Grupo arquivado continua
  // pertencendo àquela Igreja. Filtrar aqui faria essas Ações perderem a
  // Igreja e sumirem do agrupamento, sem erro nenhum.
  final groups = await ref.watch(allGroupsProvider.future);
  final churchByGroup = {for (final g in groups) g.id: g.churchId};

  final profileRepo = ref.watch(profileRepositoryProvider);
  final creatorsWithoutGroup =
      actions.where((a) => a.groupId == null).map((a) => a.creatorId).toSet();
  final profiles = await Future.wait(creatorsWithoutGroup.map(profileRepo.fetchPublicProfile));
  final churchByCreator = {for (final p in profiles) p.id: p.churchId};

  return actions.map((action) {
    final churchId =
        action.groupId != null ? churchByGroup[action.groupId] : churchByCreator[action.creatorId];
    return ActionWithChurch(action: action, churchId: churchId);
  }).toList();
});

final actionProvider = FutureProvider.autoDispose.family<Action, String>((ref, id) {
  return ref.watch(actionRepositoryProvider).fetchAction(id);
});

final attendeesProvider =
    FutureProvider.autoDispose.family<List<AttendanceWithProfile>, String>((ref, actionId) {
  return ref.watch(actionRepositoryProvider).fetchAttendees(actionId);
});

/// Contagem de presenças por Ação, para a listagem (FR-009).
///
/// Uma consulta agregada para a lista inteira. Não traz identidade de ninguém
/// — ver `ActionRepository.fetchConfirmationCounts`.
final confirmationCountsProvider =
    FutureProvider.autoDispose<Map<String, ConfirmationCounts>>((ref) {
  return ref.watch(actionRepositoryProvider).fetchConfirmationCounts();
});

/// O marcador de "última vez que vi `/acoes`". Nunca fala com o servidor —
/// ver `ActionsSeenRepository`.
final actionsSeenRepositoryProvider = Provider<ActionsSeenRepository>((ref) {
  return const ActionsSeenRepository();
});

/// Ids de Ação que quem está vendo fechou na faixa de destaque.
///
/// **Só em memória, de propósito.** Fechar vale para esta sessão do app: no
/// próximo cold start o item volta se ainda for avulsa ou ainda for nova pelo
/// marcador. É decisão explícita do dono do app, não efeito colateral —
/// gravar isto em disco ou no banco criaria um estado por Ação e por pessoa
/// que nenhuma tela precisa.
///
/// Sem `autoDispose`: sair de `/acoes` e voltar na mesma sessão não pode
/// ressuscitar o que a pessoa acabou de fechar.
///
/// `NotifierProvider`, e não o `StateProvider` previsto no design: o Riverpod
/// 3 tirou `StateProvider` do export principal (só sobrou em
/// `flutter_riverpod/legacy.dart`). Mesmo comportamento, API atual.
class DismissedHighlights extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void dismiss(String actionId) => state = {...state, actionId};
}

final dismissedHighlightsProvider =
    NotifierProvider<DismissedHighlights, Set<String>>(DismissedHighlights.new);

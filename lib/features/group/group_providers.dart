import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../profile/domain/profile.dart';
import 'data/group_repository.dart';
import 'domain/archive_preview.dart';
import 'domain/group_category.dart';
import 'domain/group.dart';

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepository(ref.watch(supabaseClientProvider));
});

final groupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchGroups();
});

final groupCategoriesProvider = FutureProvider<List<GroupCategory>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchCategories();
});

final groupProvider = FutureProvider.autoDispose.family<Group, String>((ref, id) {
  return ref.watch(groupRepositoryProvider).fetchGroup(id);
});

/// Todos os Grupos, inclusive arquivados — só para resolver a Igreja de Ações
/// antigas. Ver `GroupRepository.fetchAllGroups`.
final allGroupsProvider = FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchAllGroups();
});

final archivePreviewProvider =
    FutureProvider.autoDispose.family<ArchivePreview, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchArchivePreview(groupId);
});

/// Só o Administrador do distrito tem tela para isto (FR-019).
final archivedGroupsProvider =
    FutureProvider.autoDispose<List<Group>>((ref) {
  return ref.watch(groupRepositoryProvider).fetchArchivedGroups();
});

final membersProvider =
    FutureProvider.autoDispose.family<List<PublicProfile>, String>((ref, groupId) {
  return ref.watch(groupRepositoryProvider).fetchMembers(groupId);
});

/// Os Grupos de que eu participo — uma consulta, não uma por card.
///
/// **`autoDispose`, e isso é a correção de um defeito medido.** Sem ele o
/// resultado ficava cacheado pela vida do app: participar de um Grupo e voltar
/// para `/acoes` na mesma sessão mostrava a faixa sem a novidade daquele
/// Grupo — medido em 2026-08-13, `neutro=0` e a consulta nem refeita, só
/// voltando ao normal depois de reiniciar o app. E o marcador avançava nessa
/// visita, porque a lista e os Grupos "carregaram com sucesso" — só que
/// respondendo a pergunta de antes de a pessoa entrar no Grupo. A novidade era
/// consumida sem nunca ter sido mostrada.
///
/// A alternativa era invalidar em cada lugar que mexe em `participacoes_grupo`
/// — Participar, Sair, e criar um Grupo (onde o trigger insere o Dono). Foi
/// descartada porque o defeito É alguém ter esquecido um desses lugares, e a
/// lista só cresce. `autoDispose` responde a pergunta uma vez por abertura de
/// tela, que é a frequência que a faixa precisa, e não depende de ninguém
/// lembrar.
final myGroupIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(groupRepositoryProvider).fetchMyGroupIds();
});

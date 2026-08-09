import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../perfil/domain/profile.dart';
import 'data/group_repository.dart';
import 'domain/group_category.dart';
import 'domain/group.dart';

final grupoRepositoryProvider = Provider<GrupoRepository>((ref) {
  return GrupoRepository(ref.watch(supabaseClientProvider));
});

final gruposProvider = FutureProvider.autoDispose<List<Grupo>>((ref) {
  return ref.watch(grupoRepositoryProvider).fetchGrupos();
});

final categoriasGrupoProvider = FutureProvider<List<CategoriaGrupo>>((ref) {
  return ref.watch(grupoRepositoryProvider).fetchCategorias();
});

final grupoProvider = FutureProvider.autoDispose.family<Grupo, String>((ref, id) {
  return ref.watch(grupoRepositoryProvider).fetchGrupo(id);
});

final participantesProvider =
    FutureProvider.autoDispose.family<List<PublicProfile>, String>((ref, grupoId) {
  return ref.watch(grupoRepositoryProvider).fetchParticipantes(grupoId);
});

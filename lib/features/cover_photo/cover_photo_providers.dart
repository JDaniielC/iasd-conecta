import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_upload.dart';
import '../../core/providers.dart';
import 'data/cover_photo_repository.dart';
import 'domain/cover_photo.dart';

final coverPhotoRepositoryProvider = Provider<CoverPhotoRepository>((ref) {
  return CoverPhotoRepository(ref.watch(supabaseClientProvider));
});

/// O seletor de imagem.
///
/// É provider por um motivo só: sem ele, **o caminho de falha do envio não tem
/// como ser testado**. O widget construía `ImageUpload()` na mão, então
/// nenhum teste conseguia chegar às etapas que vêm depois da escolha — que são
/// justamente as que FR-031 governa, e que passaram seis rodadas de
/// convergência sem um teste sequer.
final imageUploadProvider = Provider<ImageUpload>((ref) => ImageUpload());

/// A capa de um Grupo, ou `null` se ele não tem. **Grupo sem capa é estado
/// normal**, não erro nem carregamento eterno (FR-002).
final groupCoverPhotoProvider =
    FutureProvider.autoDispose.family<CoverPhoto?, String>((ref, groupId) {
  return ref.watch(coverPhotoRepositoryProvider).fetchForGroup(groupId);
});

/// A capa de uma Ação, ou `null`.
final actionCoverPhotoProvider =
    FutureProvider.autoDispose.family<CoverPhoto?, String>((ref, actionId) {
  return ref.watch(coverPhotoRepositoryProvider).fetchForAction(actionId);
});

/// A chave de família das capas em lote: os ids **ordenados** e juntados.
///
/// Parece cerimônia e não é — é o conserto de um laço de rede medido.
///
/// A chave era a própria `List<String>`, e **`List` não implementa `==` por
/// valor**: duas listas com o mesmo conteúdo são famílias diferentes. Como as
/// telas montam a lista dentro do `build`, cada quadro criava um provider novo,
/// que consultava, que completava, que reconstruía. Medido:
/// **31 consultas em 30 quadros**, nas duas listagens principais do app.
/// `String` tem igualdade por valor e fecha isso.
///
/// **Ordenar** resolve a segunda metade: a listagem de Grupos tem alternador de
/// ordenação, e sem ordenar a chave trocar a ordem refaria a consulta inteira
/// por nada — os Grupos são os mesmos.
///
/// Quem chamar `groupCoverPhotosProvider` ou `actionCoverPhotosProvider` passa
/// por aqui. Montar a chave à mão traz o laço de volta.
String coverPhotosKey(List<String> ids) => (ids.toList()..sort()).join(',');

List<String> _idsFromKey(String key) => key.isEmpty ? const [] : key.split(',');

/// As capas de uma lista de Grupos, numa consulta só.
///
/// A lista **espera** este provider junto com os Grupos, para os cards
/// nascerem do tamanho final. Uma consulta por card faria a lista pular
/// conforme cada imagem chegasse (FR-007).
///
/// A chave vem de [coverPhotosKey], sempre.
final groupCoverPhotosProvider = FutureProvider.autoDispose
    .family<Map<String, CoverPhoto>, String>((ref, key) {
  return ref
      .watch(coverPhotoRepositoryProvider)
      .fetchForGroups(_idsFromKey(key));
});

/// O mesmo para Ações.
final actionCoverPhotosProvider = FutureProvider.autoDispose
    .family<Map<String, CoverPhoto>, String>((ref, key) {
  return ref
      .watch(coverPhotoRepositoryProvider)
      .fetchForActions(_idsFromKey(key));
});

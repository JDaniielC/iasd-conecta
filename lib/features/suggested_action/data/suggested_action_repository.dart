import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/suggested_action.dart';

/// Único ponto de acesso a `public.acoes_sugeridas`. Escrita restrita a
/// Administrador do distrito só por RLS (sem função `SECURITY DEFINER` —
/// ver research.md).
class SuggestedActionRepository {
  SuggestedActionRepository(this._client);

  final SupabaseClient _client;

  /// FR-004: sugestões pra Ação candidata — a Categoria vem do Grupo pai
  /// (`grupos.categoria`, texto), então primeiro resolve o id da
  /// Categoria por nome, depois busca as sugestões por esse id. Sem
  /// Categoria com esse nome cadastrada, retorna lista vazia (FR-008).
  Future<List<SuggestedAction>> fetchByCategoryName(String categoryName) async {
    final category = await _client
        .from('categorias_grupo')
        .select('id')
        .eq('nome', categoryName)
        .maybeSingle();
    if (category == null) return [];
    return fetchByCategoryId(category['id'] as String);
  }

  /// FR-005: sugestões filtradas pela Categoria escolhida na tela de Ação
  /// avulsa (nunca persistida, FR-006).
  Future<List<SuggestedAction>> fetchByCategoryId(String categoryId) async {
    final rows = await _client
        .from('acoes_sugeridas')
        .select()
        .eq('categoria_id', categoryId);
    return rows.map(SuggestedAction.fromMap).toList();
  }

  Future<List<SuggestedAction>> fetchAll() async {
    final rows = await _client.from('acoes_sugeridas').select().order('nome');
    return rows.map(SuggestedAction.fromMap).toList();
  }

  Future<void> create({required String categoryId, required String name}) async {
    await _client.from('acoes_sugeridas').insert({
      'categoria_id': categoryId,
      'nome': name.trim(),
    });
  }

  /// A recusa da policy `acoes_sugeridas_delete_admin` é **ausência, não
  /// erro**: quem não é Administrador do distrito recebe `DELETE 0` e sucesso,
  /// porque a linha deixa de existir para aquela sessão. Sem o `.select()`
  /// abaixo, esta chamada reportava que a sugestão saiu enquanto ela continuava
  /// na lista para todo mundo. Medido em 2026-08-20 — ver
  /// `test/integration/acao_sugerida_remocao_test.dart`.
  Future<void> delete(String id) async {
    final affected =
        await _client.from('acoes_sugeridas').delete().eq('id', id).select();
    if (affected.isEmpty) {
      throw StateError('Não deu pra remover agora.');
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../perfil/domain/perfil.dart';
import '../domain/categoria_grupo.dart';
import '../domain/grupo.dart';

/// Único ponto de acesso a `grupos`, `participacoes_grupo` e
/// `categorias_grupo`.
///
/// Participantes são sempre lidos via RPC `perfil_publico` (feature 001),
/// nunca por `select` direto em `perfis` — mesmo invariante de privacidade
/// (idade nunca exposta) reaplicado aqui sem reinventar nada.
class GrupoRepository {
  GrupoRepository(this._client);

  final SupabaseClient _client;

  Future<List<Grupo>> fetchGrupos() async {
    final rows = await _client.from('grupos').select().order('created_at');
    return rows.map(Grupo.fromMap).toList();
  }

  Future<Grupo> fetchGrupo(String id) async {
    final row = await _client.from('grupos').select().eq('id', id).single();
    return Grupo.fromMap(row);
  }

  Future<List<CategoriaGrupo>> fetchCategorias() async {
    final rows = await _client.from('categorias_grupo').select().order('nome');
    return rows.map(CategoriaGrupo.fromMap).toList();
  }

  Future<void> criarGrupo(NovoGrupo grupo) async {
    final uid = _client.auth.currentUser!.id;
    final perfil = await _client
        .from('perfis')
        .select('igreja_id')
        .eq('id', uid)
        .single();
    await _client
        .from('grupos')
        .insert(grupo.toInsertMap(donoId: uid, igrejaId: perfil['igreja_id'] as String?));
  }

  Future<void> editarGrupo(
    String id, {
    String? nome,
    String? categoria,
    String? detalhes,
  }) async {
    final valores = <String, dynamic>{
      if (nome != null) 'nome': nome.trim(),
      if (categoria != null) 'categoria': categoria.trim(),
      if (detalhes != null) 'detalhes': detalhes.trim().isEmpty ? null : detalhes.trim(),
    };
    if (valores.isEmpty) return;
    await _client.from('grupos').update(valores).eq('id', id);
  }

  Future<List<String>> fetchParticipanteIds(String grupoId) async {
    final rows = await _client
        .from('participacoes_grupo')
        .select('usuario_id')
        .eq('grupo_id', grupoId);
    return rows.map((r) => r['usuario_id'] as String).toList();
  }

  Future<List<PerfilPublico>> fetchParticipantes(String grupoId) async {
    final ids = await fetchParticipanteIds(grupoId);
    final perfis = await Future.wait(ids.map((id) => _fetchPerfilPublico(id)));
    return perfis;
  }

  Future<PerfilPublico> _fetchPerfilPublico(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PerfilPublico.fromMap(row);
  }

  /// FR-013: idempotente — participar de novo não é erro nem duplica.
  Future<void> participar(String grupoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('participacoes_grupo').upsert(
      {'grupo_id': grupoId, 'usuario_id': uid},
      onConflict: 'grupo_id,usuario_id',
      ignoreDuplicates: true,
    );
  }

  /// FR-007/FR-012: sair é auto-serviço, mas o Dono atual é bloqueado pelo
  /// trigger `participacoes_grupo_dono_nao_sai_sem_transferir` no banco.
  Future<void> sair(String grupoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('participacoes_grupo')
        .delete()
        .eq('grupo_id', grupoId)
        .eq('usuario_id', uid);
  }

  /// FR-010: só o Dono consegue (garantido pela RLS de `participacoes_grupo`).
  Future<void> removerParticipante(String grupoId, String usuarioId) async {
    await _client
        .from('participacoes_grupo')
        .delete()
        .eq('grupo_id', grupoId)
        .eq('usuario_id', usuarioId);
  }

  /// FR-011: só transfere pra quem já participa (garantido pelo trigger
  /// `grupos_dono_deve_participar` no banco).
  Future<void> transferirPosse(String grupoId, String novoDonoId) async {
    await _client.from('grupos').update({'dono_id': novoDonoId}).eq('id', grupoId);
  }
}

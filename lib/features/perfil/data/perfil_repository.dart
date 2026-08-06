import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/church.dart';
import '../domain/profile.dart';

/// Único ponto de acesso a `public.perfis` e `public.igrejas`.
///
/// Leitura de Perfil de outro Usuário sempre passa pela RPC `perfil_publico`
/// (nunca `select` direto na tabela) — é a tabela base que tem RLS
/// restringindo linhas ao dono, então um `select` direto de outro id sempre
/// devolve vazio, por design (idade nunca exposta, ver FR-004).
class PerfilRepository {
  PerfilRepository(this._client);

  final SupabaseClient _client;

  Future<bool> hasPerfil() async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('perfis')
        .select('id')
        .eq('id', uid)
        .maybeSingle();
    return row != null;
  }

  Future<List<Church>> fetchChurches() async {
    final rows = await _client.from('igrejas').select().order('nome');
    return rows.map(Church.fromMap).toList();
  }

  Future<void> criarPerfil(Profile perfil) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('perfis').insert(perfil.toInsertMap(id: uid));
  }

  Future<PublicProfile> fetchPerfilPublico(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }
}

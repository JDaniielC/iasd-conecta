import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/church.dart';
import '../domain/profile.dart';

/// Único ponto de acesso a `public.perfis` e `public.igrejas`.
///
/// `updateMyProfile` é a **primeira consumidora** da policy
/// `perfis_update_own`, criada em 2026-07-23 e nunca usada até aqui: a
/// permissão de corrigir o próprio Perfil existia no banco desde o começo, e
/// nenhuma linha de código a exercia — o titular dependia de e-mail para
/// corrigir o próprio nome.
///
/// Leitura de Perfil de outro Usuário sempre passa pela RPC `perfil_publico`
/// (nunca `select` direto na tabela) — é a tabela base que tem RLS
/// restringindo linhas ao dono, então um `select` direto de outro id sempre
/// devolve vazio, por design (idade nunca exposta, ver FR-004).
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<bool> hasProfile() async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('perfis')
        .select('id')
        .eq('id', uid)
        .maybeSingle();
    return row != null;
  }

  Future<Profile> fetchMyProfile() async {
    final uid = _client.auth.currentUser!.id;
    final row =
        await _client.from('perfis').select().eq('id', uid).maybeSingle();
    if (row == null) {
      throw StateError('Perfil não encontrado para a sessão atual');
    }
    return Profile.fromMap(row);
  }

  /// Uma chamada só, de propósito.
  ///
  /// As cinco colunas mudam juntas ou não mudam — um `update` é atômico, então
  /// não existe estado pela metade sem precisar de transação nem de RPC. Se
  /// falhar, o banco fica exatamente como estava.
  Future<void> updateMyProfile(Profile profile) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('perfis').update(profile.toUpdateMap()).eq('id', uid);
  }

  Future<List<Church>> fetchChurches() async {
    final rows = await _client.from('igrejas').select().order('nome');
    return rows.map(Church.fromMap).toList();
  }

  Future<void> createProfile(Profile profile) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('perfis').insert(profile.toInsertMap(id: uid));
  }

  /// Exclusão de conta (feature 009, LGPD art. 18 VI). Toda a regra vive na
  /// função `excluir_minha_conta()`, numa transação só — o cliente não
  /// orquestra nada, senão uma queda de rede no meio deixaria um Perfil
  /// parcialmente anonimizado.
  ///
  /// O `signOut()` não é decorativo: apagar o `auth.users` invalida o refresh
  /// token, mas o JWT já emitido continua válido até expirar, e sem isto o app
  /// seguiria parecendo logado (FR-004).
  Future<void> deleteMyAccount() async {
    await _client.rpc('excluir_minha_conta');
    await _client.auth.signOut();
  }

  Future<PublicProfile> fetchPublicProfile(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }
}

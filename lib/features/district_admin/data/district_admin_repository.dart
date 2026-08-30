import 'package:supabase_flutter/supabase_flutter.dart';

/// Único ponto de acesso a `administradores_distrito` e às escritas
/// administrativas em `igrejas` (adicionar/arquivar). Leitura de Church
/// (ativas/arquivadas) continua em `PerfilRepository.fetchChurches` — RLS
/// já decide o que cada sessão vê, sem precisar de um método duplicado
/// aqui.
class DistrictAdminRepository {
  DistrictAdminRepository(this._client);

  final SupabaseClient _client;

  Future<bool> isDistrictAdmin() async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('administradores_distrito')
        .select('usuario_id')
        .eq('usuario_id', uid)
        .maybeSingle();
    return row != null;
  }

  /// FR-001/FR-002/FR-003: garantido pelo trigger no banco — só quem já é
  /// Administrador promove, e só quem tem Conta pode ser promovido.
  Future<void> promoteToAdmin(String targetUserId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('administradores_distrito').insert({
      'usuario_id': targetUserId,
      'promovido_por': uid,
    });
  }

  /// FR-004: só Administrador consegue (garantido pela RLS de `igrejas`).
  Future<void> addChurch(String name) async {
    await _client.from('igrejas').insert({'nome': name.trim()});
  }

  /// FR-005/FR-010: arquivar é só um `UPDATE`, nunca `DELETE` — preserva
  /// todo vínculo histórico. Reenviar o mesmo id é não-operação (a linha já
  /// fica com `arquivada_em` preenchido).
  /// Zero linhas é recusa: só Administrador do distrito arquiva Igreja.
  Future<void> archiveChurch(String churchId) async {
    final affected = await _client
        .from('igrejas')
        .update({'arquivada_em': DateTime.now().toUtc().toIso8601String()})
        .eq('id', churchId)
        .select('id');
    if (affected.isEmpty) {
      throw StateError('Não deu pra arquivar agora.');
    }
  }
}

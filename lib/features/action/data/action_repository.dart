import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/profile.dart';
import '../domain/action.dart';

/// Único ponto de acesso a `acoes` e `confirmacoes_acao`.
///
/// Status de vaga (confirmado/fila) é decidido inteiramente no banco (ver
/// research.md) — este repositório nunca envia `status`, só `acao_id` e
/// `usuario_id`. Confirmados são sempre lidos via RPC `perfil_publico`,
/// nunca `select` direto em `perfis` (mesmo invariante de privacidade das
/// features anteriores).
class ActionRepository {
  ActionRepository(this._client);

  final SupabaseClient _client;

  Future<List<Action>> fetchActions() async {
    final rows = await _client.from('acoes').select().order('data_hora');
    return rows.map(Action.fromMap).toList();
  }

  Future<Action> fetchAction(String id) async {
    final row = await _client.from('acoes').select().eq('id', id).single();
    return Action.fromMap(row);
  }

  Future<void> createAction(NewAction action) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('acoes').insert(action.toInsertMap(creatorId: uid));
  }

  Future<void> cancelAction(String id) async {
    await _client.from('acoes').update({'cancelada_em': DateTime.now().toUtc().toIso8601String()}).eq(
      'id',
      id,
    );
  }

  /// FR-012: idempotente — confirmar de novo não é erro nem duplica.
  Future<void> confirmAttendance(String acaoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('confirmacoes_acao').upsert(
      {'acao_id': acaoId, 'usuario_id': uid},
      onConflict: 'acao_id,usuario_id',
      ignoreDuplicates: true,
    );
  }

  /// FR-004: sempre auto-serviço; a promoção da fila é automática no banco.
  Future<void> withdraw(String acaoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('confirmacoes_acao')
        .delete()
        .eq('acao_id', acaoId)
        .eq('usuario_id', uid);
  }

  Future<List<AttendanceWithProfile>> fetchAttendees(String acaoId) async {
    final rows = await _client
        .from('confirmacoes_acao')
        .select('usuario_id, status')
        .eq('acao_id', acaoId)
        .order('created_at');

    final results = await Future.wait(rows.map((row) async {
      final profile = await _fetchPerfilPublico(row['usuario_id'] as String);
      final status = row['status'] == 'confirmado'
          ? AttendanceStatus.confirmed
          : AttendanceStatus.waitlist;
      return AttendanceWithProfile(profile: profile, status: status);
    }));
    return results;
  }

  Future<PublicProfile> _fetchPerfilPublico(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../perfil/domain/profile.dart';
import '../domain/acao.dart';

/// Único ponto de acesso a `acoes` e `confirmacoes_acao`.
///
/// Status de vaga (confirmado/fila) é decidido inteiramente no banco (ver
/// research.md) — este repositório nunca envia `status`, só `acao_id` e
/// `usuario_id`. Confirmados são sempre lidos via RPC `perfil_publico`,
/// nunca `select` direto em `perfis` (mesmo invariante de privacidade das
/// features anteriores).
class AcaoRepository {
  AcaoRepository(this._client);

  final SupabaseClient _client;

  Future<List<Acao>> fetchAcoes() async {
    final rows = await _client.from('acoes').select().order('data_hora');
    return rows.map(Acao.fromMap).toList();
  }

  Future<Acao> fetchAcao(String id) async {
    final row = await _client.from('acoes').select().eq('id', id).single();
    return Acao.fromMap(row);
  }

  Future<void> criarAcao(NovaAcao acao) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('acoes').insert(acao.toInsertMap(criadorId: uid));
  }

  Future<void> cancelarAcao(String id) async {
    await _client.from('acoes').update({'cancelada_em': DateTime.now().toUtc().toIso8601String()}).eq(
      'id',
      id,
    );
  }

  /// FR-012: idempotente — confirmar de novo não é erro nem duplica.
  Future<void> confirmarPresenca(String acaoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('confirmacoes_acao').upsert(
      {'acao_id': acaoId, 'usuario_id': uid},
      onConflict: 'acao_id,usuario_id',
      ignoreDuplicates: true,
    );
  }

  /// FR-004: sempre auto-serviço; a promoção da fila é automática no banco.
  Future<void> desistir(String acaoId) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('confirmacoes_acao')
        .delete()
        .eq('acao_id', acaoId)
        .eq('usuario_id', uid);
  }

  Future<List<ConfirmacaoComPerfil>> fetchConfirmados(String acaoId) async {
    final rows = await _client
        .from('confirmacoes_acao')
        .select('usuario_id, status')
        .eq('acao_id', acaoId)
        .order('created_at');

    final resultados = await Future.wait(rows.map((row) async {
      final perfil = await _fetchPerfilPublico(row['usuario_id'] as String);
      final status = row['status'] == 'confirmado'
          ? StatusConfirmacao.confirmado
          : StatusConfirmacao.fila;
      return ConfirmacaoComPerfil(perfil: perfil, status: status);
    }));
    return resultados;
  }

  Future<PublicProfile> _fetchPerfilPublico(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }
}

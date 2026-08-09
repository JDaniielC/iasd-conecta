import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/action.dart';
import '../domain/voting_round.dart';
import 'action_repository.dart';

/// Único ponto de acesso a `rodadas_votacao` e `votos`.
///
/// `fecharSeDevido` é chamada antes de toda leitura/escrita relevante numa
/// Rodada (buscar detalhes, propor candidata, votar) — implementa o
/// fechamento preguiçoso por prazo vencido (FR-008), sem job agendado (ver
/// research.md).
class RodadaRepository {
  RodadaRepository(this._client, this._acaoRepository);

  final SupabaseClient _client;
  final AcaoRepository _acaoRepository;

  Future<List<Rodada>> fetchRodadasDoGrupo(String grupoId) async {
    final rows = await _client
        .from('rodadas_votacao')
        .select()
        .eq('grupo_id', grupoId)
        .order('created_at');
    return rows.map(Rodada.fromMap).toList();
  }

  Future<Rodada> fetchRodada(String id) async {
    await fecharSeDevido(id);
    final row = await _client.from('rodadas_votacao').select().eq('id', id).single();
    return Rodada.fromMap(row);
  }

  Future<void> abrirRodada(NovaRodada rodada, {required String grupoId}) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('rodadas_votacao')
        .insert(rodada.toInsertMap(grupoId: grupoId, abertaPor: uid));
  }

  Future<List<Acao>> fetchCandidatas(String rodadaId) async {
    final rows = await _client
        .from('acoes')
        .select()
        .eq('rodada_id', rodadaId)
        .eq('confirmada', false)
        .order('created_at');
    return rows.map(Acao.fromMap).toList();
  }

  /// FR-003: propõe uma Ação candidata — `grupo_id` nunca é enviado, é
  /// sempre derivado da Rodada pelo trigger no banco.
  Future<void> proporCandidata(String rodadaId, NovaAcao candidata) async {
    await fecharSeDevido(rodadaId);
    await _acaoRepository.criarAcao(
      NovaAcao(
        nome: candidata.nome,
        dataHora: candidata.dataHora,
        local: candidata.local,
        detalhes: candidata.detalhes,
        limiteVagas: candidata.limiteVagas,
        rodadaId: rodadaId,
      ),
    );
  }

  /// FR-006: upsert — trocar de candidata atualiza a mesma linha, só a
  /// última escolha conta.
  Future<void> votar(String rodadaId, String candidataId) async {
    await fecharSeDevido(rodadaId);
    final uid = _client.auth.currentUser!.id;
    await _client.from('votos').upsert(
      {'rodada_id': rodadaId, 'usuario_id': uid, 'candidata_id': candidataId},
      onConflict: 'rodada_id,usuario_id',
    );
  }

  Future<Voto?> meuVoto(String rodadaId) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('votos')
        .select()
        .eq('rodada_id', rodadaId)
        .eq('usuario_id', uid)
        .maybeSingle();
    return row == null ? null : Voto.fromMap(row);
  }

  /// FR-008/FR-009/FR-010: não-operação se já fechada ou se o prazo ainda
  /// não venceu e ninguém forçou; `forcar` só funciona pro Dono do Grupo
  /// (checado dentro da função no banco).
  Future<void> fecharSeDevido(String rodadaId, {bool forcar = false}) async {
    await _client.rpc(
      'fechar_rodada_se_devido',
      params: {'p_rodada_id': rodadaId, 'p_forcar': forcar},
    );
  }
}

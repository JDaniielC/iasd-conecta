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
class VotingRoundRepository {
  VotingRoundRepository(this._client, this._acaoRepository);

  final SupabaseClient _client;
  final ActionRepository _acaoRepository;

  Future<List<VotingRound>> fetchRodadasDoGrupo(String groupId) async {
    final rows = await _client
        .from('rodadas_votacao')
        .select()
        .eq('grupo_id', groupId)
        .order('created_at');
    return rows.map(VotingRound.fromMap).toList();
  }

  Future<VotingRound> fetchVotingRound(String id) async {
    await closeIfDue(id);
    final row = await _client.from('rodadas_votacao').select().eq('id', id).single();
    return VotingRound.fromMap(row);
  }

  Future<void> openRound(NewVotingRound rodada, {required String groupId}) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('rodadas_votacao')
        .insert(rodada.toInsertMap(groupId: groupId, openedBy: uid));
  }

  Future<List<Action>> fetchCandidatas(String votingRoundId) async {
    final rows = await _client
        .from('acoes')
        .select()
        .eq('rodada_id', votingRoundId)
        .eq('confirmada', false)
        .order('created_at');
    return rows.map(Action.fromMap).toList();
  }

  /// FR-003: propõe uma Ação candidata — `grupo_id` nunca é enviado, é
  /// sempre derivado da Rodada pelo trigger no banco.
  Future<void> proposeCandidate(String votingRoundId, NewAction candidate) async {
    await closeIfDue(votingRoundId);
    await _acaoRepository.createAction(
      NewAction(
        name: candidate.name,
        dateTime: candidate.dateTime,
        local: candidate.local,
        details: candidate.details,
        capacity: candidate.capacity,
        votingRoundId: votingRoundId,
      ),
    );
  }

  /// FR-006: upsert — trocar de candidata atualiza a mesma linha, só a
  /// última escolha conta.
  Future<void> vote(String votingRoundId, String candidateId) async {
    await closeIfDue(votingRoundId);
    final uid = _client.auth.currentUser!.id;
    await _client.from('votos').upsert(
      {'rodada_id': votingRoundId, 'usuario_id': uid, 'candidata_id': candidateId},
      onConflict: 'rodada_id,usuario_id',
    );
  }

  Future<Vote?> myVote(String votingRoundId) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('votos')
        .select()
        .eq('rodada_id', votingRoundId)
        .eq('usuario_id', uid)
        .maybeSingle();
    return row == null ? null : Vote.fromMap(row);
  }

  /// FR-008/FR-009/FR-010: não-operação se já fechada ou se o prazo ainda
  /// não venceu e ninguém forçou; `forcar` só funciona pro Dono do Grupo
  /// (checado dentro da função no banco).
  Future<void> closeIfDue(String votingRoundId, {bool forcar = false}) async {
    await _client.rpc(
      'fechar_rodada_se_devido',
      params: {'p_rodada_id': votingRoundId, 'p_forcar': forcar},
    );
  }
}

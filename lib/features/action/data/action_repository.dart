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

  /// Contagem de presenças de TODAS as Ações, numa consulta só (FR-009).
  ///
  /// A projeção é explícita de propósito: `select()` puro traria `usuario_id`
  /// de todo mundo que confirmou presença no distrito para o cliente, e a
  /// listagem só precisa de um número. `acao_id, status` é o mínimo — o número
  /// existe sem que o cliente saiba quem é quem (Princípio II).
  ///
  /// Uma consulta para a lista inteira, não uma por Ação: reusar
  /// `fetchAttendees` por Ação seria N+1 e, pior, traria a lista nominal
  /// completa de cada uma para desenhar um número.
  Future<Map<String, ConfirmationCounts>> fetchConfirmationCounts() async {
    final rows = await _client.from('confirmacoes_acao').select('acao_id, status');

    final confirmed = <String, int>{};
    final waiting = <String, int>{};
    for (final row in rows) {
      final id = row['acao_id'] as String;
      if (row['status'] == 'confirmado') {
        confirmed[id] = (confirmed[id] ?? 0) + 1;
      } else {
        waiting[id] = (waiting[id] ?? 0) + 1;
      }
    }
    return {
      for (final id in {...confirmed.keys, ...waiting.keys})
        id: ConfirmationCounts(
          confirmed: confirmed[id] ?? 0,
          waiting: waiting[id] ?? 0,
        ),
    };
  }

  Future<Action> fetchAction(String id) async {
    final row = await _client.from('acoes').select().eq('id', id).single();
    return Action.fromMap(row);
  }

  Future<void> createAction(NewAction action) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('acoes').insert(action.toInsertMap(creatorId: uid));
  }

  /// Marca/desmarca a restrição ao Grupo (change `acao-direcionada-a-grupo`).
  ///
  /// Sem checagem de permissão aqui de propósito: quem pode é decidido por
  /// `acoes_update_criador_dono_grupo_ou_admin`. O banco recusa a mudança
  /// depois de a Ação encerrar, e recusa tornar restrita uma Ação que o próprio
  /// autor da escrita deixaria de enxergar — as duas viram exceção sozinhas.
  ///
  /// **O `.select()` no fim não é enfeite.** Recusa por RLS de `update` não
  /// levanta erro: devolve ZERO LINHA, calada. Sem ler o retorno, quem não tem
  /// permissão veria o interruptor voltar sozinho e nenhuma explicação. Medido
  /// em `test/integration/acao_restrita_quem_restringe_test.dart`.
  ///
  /// Ler o retorno é seguro nos dois sentidos: restringir só é possível para
  /// quem continua enxergando a Ação (senão o banco já teria estourado), e
  /// desmarcar deixa a linha mais visível. Ou seja, resposta vazia quer dizer
  /// "não mudou nada", nunca "mudou e sumiu".
  Future<void> setRestrictedToGroup(String id, bool restricted) async {
    final rows = await _client
        .from('acoes')
        .update({'restrita_ao_grupo': restricted})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw StateError('a restrição não foi alterada: escrita sem permissão');
    }
  }

  /// Zero linhas aqui é recusa da RLS — quem não criou a Ação não a cancela, e
  /// a policy responde fazendo a linha não existir para aquela sessão, sem
  /// levantar erro. Medido em `test/integration/escrita_recusada_test.dart`.
  Future<void> cancelAction(String id) async {
    final affected = await _client
        .from('acoes')
        .update({'cancelada_em': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    if (affected.isEmpty) {
      throw StateError('Não deu pra cancelar agora. Tente de novo.');
    }
  }

  /// FR-012: idempotente — confirmar de novo não é erro nem duplica.
  Future<void> confirmAttendance(String actionId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('confirmacoes_acao').upsert(
      {'acao_id': actionId, 'usuario_id': uid},
      onConflict: 'acao_id,usuario_id',
      ignoreDuplicates: true,
    );
  }

  /// FR-004: sempre auto-serviço; a promoção da fila é automática no banco.
  ///
  /// **Zero linhas aqui tem DUAS causas opostas**, e a contagem sozinha não as
  /// separa — medido em `test/integration/desistencia_zero_ambiguo_test.dart`:
  ///
  ///   - a pessoa não estava confirmada, e não havia nada a apagar. Está tudo
  ///     certo, e não é erro.
  ///   - `confirmacoes_acao_delete_self` recusou por
  ///     `public.acao_encerrada(acao_id)`, que existe para
  ///     `confirmacoes_acao_promover_fila` não promover ninguém depois do
  ///     encerramento (migration `20260809174740`). Aí ela **continua constando
  ///     como presente num encontro que já aconteceu**, e precisa ouvir isso.
  ///
  /// A leitura extra só acontece no caminho vazio. Conferir antes gastaria duas
  /// viagens em toda desistência para cobrir o caso raro — e ainda deixaria a
  /// corrida entre a checagem e a escrita de pé.
  Future<void> withdraw(String actionId) async {
    final uid = _client.auth.currentUser!.id;
    final affected = await _client
        .from('confirmacoes_acao')
        .delete()
        .eq('acao_id', actionId)
        .eq('usuario_id', uid)
        .select('usuario_id');
    if (affected.isNotEmpty) return;

    final action = await fetchAction(actionId);
    if (actionTimeStatus(action.dateTime, DateTime.now()) ==
        ActionTimeStatus.ended) {
      throw StateError('Essa Ação já encerrou. Sua presença continua registrada.');
    }
    // Ação aberta e nada apagado: a pessoa não estava confirmada. O estado que
    // a tela recarrega já mostra isso, e inventar erro aqui seria pior.
  }

  Future<List<AttendanceWithProfile>> fetchAttendees(String actionId) async {
    final rows = await _client
        .from('confirmacoes_acao')
        .select('usuario_id, status')
        .eq('acao_id', actionId)
        .order('created_at');

    final results = await Future.wait(rows.map((row) async {
      final profile = await _fetchPublicProfile(row['usuario_id'] as String);
      final status = row['status'] == 'confirmado'
          ? AttendanceStatus.confirmed
          : AttendanceStatus.waitlist;
      return AttendanceWithProfile(profile: profile, status: status);
    }));
    return results;
  }

  Future<PublicProfile> _fetchPublicProfile(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }
}

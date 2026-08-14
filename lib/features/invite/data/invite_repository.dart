import 'package:supabase_flutter/supabase_flutter.dart';

import '../../action/domain/action.dart';
import '../domain/action_invite.dart';
import '../domain/invite_contact.dart';
import '../domain/invite_contact_group.dart';

/// Único ponto de acesso a `convites_acao` e às duas funções da change
/// `convite-para-acao`.
///
/// A regra de ouro aqui é o número de idas ao servidor. O caminho que existia
/// antes desta change era N+1: um RPC `perfil_publico` por membro
/// (`group_repository.dart:151-161`), repetido por Grupo, numa tela que abre
/// com todos os Grupos da pessoa. `contatos_para_convite` existe para isso ser
/// UMA chamada, já agrupada e já sabendo quem foi convidado.
class InviteRepository {
  InviteRepository(this._client);

  final SupabaseClient _client;

  /// Contatos convidáveis, agrupados por Grupo. Uma chamada.
  ///
  /// Nenhum id de Grupo é enviado, e isso é a defesa, não um esquecimento: a
  /// função é `security definer` sobre `perfis`, e aceitar um Grupo do cliente
  /// entregaria a lista de nomes de qualquer Grupo do distrito.
  Future<List<InviteContactGroup>> fetchContacts(String actionId) async {
    final rows = await _client
        .rpc('contatos_para_convite', params: {'p_acao_id': actionId}) as List;

    final porGrupo = <String, List<InviteContact>>{};
    final nomes = <String, String>{};
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final groupId = row['grupo_id'] as String;
      nomes[groupId] = row['grupo_nome'] as String;
      (porGrupo[groupId] ??= []).add(
        InviteContact(
          userId: row['usuario_id'] as String,
          displayName: row['nome_exibido'] as String,
          alreadyInvited: row['ja_convidado'] as bool,
          alreadyConfirmed: row['ja_confirmou'] as bool,
        ),
      );
    }
    // A ordem vem do `order by` da função (Grupo, depois nome de exibição);
    // reordenar aqui inventaria uma segunda ordenação para divergir da primeira.
    return [
      for (final entry in porGrupo.entries)
        InviteContactGroup(
          groupId: entry.key,
          groupName: nomes[entry.key]!,
          contacts: entry.value,
        ),
    ];
  }

  /// Convida em lote e devolve uma linha POR PESSOA PEDIDA.
  ///
  /// Não é `RETURNING`: com `on conflict do nothing`, quem já tinha convite não
  /// voltaria, e a tela leria a ausência como falha — mostrando erro para uma
  /// operação que deu certo.
  Future<List<InviteResult>> invite(
    String actionId,
    String groupId,
    List<String> userIds,
  ) async {
    final rows = await _client.rpc('convidar_para_acao', params: {
      'p_acao_id': actionId,
      'p_grupo_id': groupId,
      'p_convidados': userIds,
    }) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(InviteResult.fromMap)
        .toList();
  }

  /// Convites recebidos, com a Ação e o nome do Grupo de origem.
  ///
  /// **Duas chamadas, constantes — não N+1.** A primeira traz os convites com a
  /// Ação e o Grupo embutidos; a segunda traz as confirmações **da própria
  /// pessoa** para aquelas Ações. Trazer as confirmações embutidas na primeira
  /// puxaria o par nominal de todo mundo que confirmou em cada Ação convidada,
  /// para desenhar um booleano sobre si mesma.
  Future<List<ReceivedInvite>> fetchReceivedInvites() async {
    final uid = _client.auth.currentUser!.id;
    final rows = await _client
        .from('convites_acao')
        .select('*, grupos(nome), acoes(*)')
        .eq('convidado_id', uid)
        .order('created_at', ascending: false);

    if (rows.isEmpty) return const [];

    final actionIds = rows
        .map((r) => r['acao_id'] as String)
        .toSet()
        .toList();
    final minhas = await _client
        .from('confirmacoes_acao')
        .select('acao_id')
        .eq('usuario_id', uid)
        .inFilter('acao_id', actionIds);
    final confirmadas =
        minhas.map((r) => r['acao_id'] as String).toSet();

    return [
      for (final row in rows)
        ReceivedInvite(
          invite: ActionInvite.fromMap(row),
          // `grupos` sempre vem: `grupos_select_public` é `using (true)`.
          groupName: (row['grupos'] as Map<String, dynamic>)['nome'] as String,
          // `acoes` pode vir nulo: Ação restrita ao Grupo deixa de ser legível
          // quando a pessoa sai dele. Convite apontando para o que não abre é
          // convite morto, e `isOpen` trata assim.
          action: row['acoes'] == null
              ? null
              : Action.fromMap(row['acoes'] as Map<String, dynamic>),
          alreadyConfirmed: confirmadas.contains(row['acao_id'] as String),
        ),
    ];
  }

  /// Recusa o próprio convite.
  ///
  /// `.select()` no fim pelo mesmo motivo de `setRestrictedToGroup`: recusa por
  /// RLS de `update` não levanta erro, devolve zero linha. Sem ler o retorno, a
  /// tela diria que recusou quando não recusou.
  Future<void> decline(String actionId, String groupId) async {
    final rows = await _client
        .from('convites_acao')
        .update({'recusado_em': DateTime.now().toUtc().toIso8601String()})
        .eq('acao_id', actionId)
        .eq('grupo_id', groupId)
        .select('acao_id');
    if (rows.isEmpty) {
      throw StateError('o convite não foi recusado: escrita sem permissão');
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/profile.dart';
import '../domain/archive_preview.dart';
import '../domain/group_category.dart';
import '../domain/group.dart';

/// Único ponto de acesso a `grupos`, `participacoes_grupo` e
/// `categorias_grupo`.
///
/// Participantes são sempre lidos via RPC `perfil_publico` (feature 001),
/// nunca por `select` direto em `perfis` — mesmo invariante de privacidade
/// (idade nunca exposta) reaplicado aqui sem reinventar nada.
class GroupRepository {
  GroupRepository(this._client);

  final SupabaseClient _client;

  /// Só Grupos ativos. Grupo arquivado sai do caminho de todo mundo (FR-010)
  /// — inclusive de quem participava, que não deve mais ser lembrado dele.
  Future<List<Group>> fetchGroups() async {
    final rows = await _client
        .from('grupos')
        .select()
        .filter('arquivado_em', 'is', null)
        .order('created_at');
    return rows.map(Group.fromMap).toList();
  }

  /// Todos os Grupos, **inclusive os arquivados**.
  ///
  /// Existe por um motivo só: resolver a Igreja de uma Ação
  /// (`actionsWithChurchProvider`). Ação passada de um Grupo arquivado
  /// continua existindo e continua pertencendo àquela Igreja — se esta consulta
  /// filtrasse arquivados, essas Ações perderiam a Igreja e sumiriam do
  /// agrupamento da lista, em silêncio. Não usar para listar Grupo.
  Future<List<Group>> fetchAllGroups() async {
    final rows = await _client.from('grupos').select().order('created_at');
    return rows.map(Group.fromMap).toList();
  }

  /// Só o Administrador do distrito tem tela para isto (FR-019).
  Future<List<Group>> fetchArchivedGroups() async {
    final rows = await _client
        .from('grupos')
        .select()
        .not('arquivado_em', 'is', null)
        .order('arquivado_em', ascending: false);
    return rows.map(Group.fromMap).toList();
  }

  /// Os quatro números que a confirmação de arquivamento mostra.
  ///
  /// Quatro consultas de leitura, sem RPC nova: as tabelas já têm select
  /// público e nenhum destes números é segredo. Inventar uma função de banco
  /// aqui seria complexidade sem regra que a justifique (Princípio V).
  Future<ArchivePreview> fetchArchivePreview(String groupId) async {
    final now = DateTime.now().toUtc().toIso8601String();

    final futureActions = await _client
        .from('acoes')
        .select('id')
        .eq('grupo_id', groupId)
        .eq('confirmada', true)
        .filter('cancelada_em', 'is', null)
        .gt('data_hora', now);
    final futureActionIds =
        futureActions.map((row) => row['id'] as String).toList();

    var attendances = 0;
    if (futureActionIds.isNotEmpty) {
      final rows = await _client
          .from('confirmacoes_acao')
          .select('acao_id')
          .inFilter('acao_id', futureActionIds);
      attendances = rows.length;
    }

    final openRounds = await _client
        .from('rodadas_votacao')
        .select('id')
        .eq('grupo_id', groupId)
        .filter('fechada_em', 'is', null);

    final members = await _client
        .from('participacoes_grupo')
        .select('usuario_id')
        .eq('grupo_id', groupId);

    return ArchivePreview(
      futureActions: futureActionIds.length,
      confirmedAttendances: attendances,
      openVotingRounds: openRounds.length,
      members: members.length,
    );
  }

  Future<void> archiveGroup(String groupId) async {
    await _client.rpc('arquivar_grupo', params: {'p_grupo_id': groupId});
  }

  Future<void> unarchiveGroup(String groupId) async {
    await _client.rpc('desarquivar_grupo', params: {'p_grupo_id': groupId});
  }

  Future<Group> fetchGroup(String id) async {
    final row = await _client.from('grupos').select().eq('id', id).single();
    return Group.fromMap(row);
  }

  Future<List<GroupCategory>> fetchCategories() async {
    final rows = await _client.from('categorias_grupo').select().order('nome');
    return rows.map(GroupCategory.fromMap).toList();
  }

  Future<void> createGroup(NewGroup group) async {
    final uid = _client.auth.currentUser!.id;
    final profile = await _client
        .from('perfis')
        .select('igreja_id')
        .eq('id', uid)
        .single();
    await _client
        .from('grupos')
        .insert(group.toInsertMap(ownerId: uid, churchId: profile['igreja_id'] as String?));
  }

  Future<void> updateGroup(
    String id, {
    String? name,
    String? category,
    String? details,
  }) async {
    final values = <String, dynamic>{
      if (name != null) 'nome': name.trim(),
      if (category != null) 'categoria': category.trim(),
      if (details != null) 'detalhes': details.trim().isEmpty ? null : details.trim(),
    };
    if (values.isEmpty) return;
    await _client.from('grupos').update(values).eq('id', id);
  }

  Future<List<String>> fetchMemberIds(String groupId) async {
    final rows = await _client
        .from('participacoes_grupo')
        .select('usuario_id')
        .eq('grupo_id', groupId);
    return rows.map((r) => r['usuario_id'] as String).toList();
  }

  /// Os Grupos de que a pessoa da sessão atual participa, numa consulta só.
  ///
  /// Uma consulta para a lista inteira, e não `fetchMemberIds` por card: o
  /// mesmo N+1 que `ActionRepository.fetchConfirmationCounts` já evita de
  /// propósito. Sem sessão (Visitante sem Conta) não há o que perguntar —
  /// devolve vazio sem ir ao servidor.
  ///
  /// O filtro por `usuario_id` é explícito porque a RLS de
  /// `participacoes_grupo` NÃO restringe o select às próprias linhas (é ela
  /// que permite `fetchMemberIds` listar os membros de um Grupo alheio).
  Future<Set<String>> fetchMyGroupIds() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const <String>{};
    final rows = await _client
        .from('participacoes_grupo')
        .select('grupo_id')
        .eq('usuario_id', uid);
    return rows.map((r) => r['grupo_id'] as String).toSet();
  }

  Future<List<PublicProfile>> fetchMembers(String groupId) async {
    final ids = await fetchMemberIds(groupId);
    final profiles = await Future.wait(ids.map((id) => _fetchPublicProfile(id)));
    return profiles;
  }

  Future<PublicProfile> _fetchPublicProfile(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }

  /// FR-013: idempotente — participar de novo não é erro nem duplica.
  Future<void> join(String groupId) async {
    final uid = _client.auth.currentUser!.id;
    await _client.from('participacoes_grupo').upsert(
      {'grupo_id': groupId, 'usuario_id': uid},
      onConflict: 'grupo_id,usuario_id',
      ignoreDuplicates: true,
    );
  }

  /// FR-007/FR-012: sair é auto-serviço, mas o Dono atual é bloqueado pelo
  /// trigger `participacoes_grupo_dono_nao_sai_sem_transferir` no banco.
  Future<void> leave(String groupId) async {
    final uid = _client.auth.currentUser!.id;
    await _client
        .from('participacoes_grupo')
        .delete()
        .eq('grupo_id', groupId)
        .eq('usuario_id', uid);
  }

  /// FR-010: só o Dono consegue (garantido pela RLS de `participacoes_grupo`).
  Future<void> removeMember(String groupId, String userId) async {
    await _client
        .from('participacoes_grupo')
        .delete()
        .eq('grupo_id', groupId)
        .eq('usuario_id', userId);
  }

  /// FR-011: só transfere pra quem já participa (garantido pelo trigger
  /// `grupos_dono_deve_participar` no banco).
  Future<void> transferOwnership(String groupId, String newOwnerId) async {
    await _client.from('grupos').update({'dono_id': newOwnerId}).eq('id', groupId);
  }
}

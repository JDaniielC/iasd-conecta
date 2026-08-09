import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/leadership_declaration.dart';

/// Toda escrita passa pelas funções `SECURITY DEFINER` do banco
/// (`declarar_lideranca`/`decidir_lideranca`) — não há `INSERT`/`UPDATE`
/// direto na tabela `liderancas` (ver research.md da feature 006).
class LeadershipRepository {
  LeadershipRepository(this._client);

  final SupabaseClient _client;

  Future<void> declare({required String groupId, required int year}) async {
    await _client.rpc('declarar_lideranca', params: {
      'p_grupo_id': groupId,
      'p_ano': year,
    });
  }

  Future<void> decide({required String declarationId, required bool approve}) async {
    await _client.rpc('decidir_lideranca', params: {
      'p_lideranca_id': declarationId,
      'p_aprovar': approve,
    });
  }

  /// Predicado gêmeo do da policy `liderancas_select_confirmada_propria_ou_admin`
  /// (feature 018). Os dois mudam juntos.
  ///
  /// A duplicação é declarada de propósito: se divergirem, o sintoma é
  /// silencioso, porque a RLS remove a linha antes de o Dart ver — ela some da
  /// tela sem erro nenhum. Filtrar só aqui é o que já existia e é literalmente
  /// o que falhou; quem protege é a policy.
  Future<List<LeadershipDeclaration>> fetchCurrentLeaders({
    required String groupId,
    required int year,
  }) async {
    final rows = await _client
        .from('liderancas')
        .select()
        .eq('grupo_id', groupId)
        .eq('ano', year)
        .not('confirmado_em', 'is', null)
        .filter('rejeitado_em', 'is', null);
    return rows.map(LeadershipDeclaration.fromMap).toList();
  }

  Future<LeadershipDeclaration?> fetchMyDeclaration({
    required String groupId,
    required int year,
  }) async {
    final uid = _client.auth.currentUser!.id;
    final row = await _client
        .from('liderancas')
        .select()
        .eq('grupo_id', groupId)
        .eq('usuario_id', uid)
        .eq('ano', year)
        .maybeSingle();
    return row == null ? null : LeadershipDeclaration.fromMap(row);
  }

  /// FR-004: lista de pendentes de todo o distrito, pro Administrador
  /// decidir — mesma tabela e policy pública de `fetchCurrentLeaders`, só
  /// com filtro diferente (ver research.md).
  Future<List<LeadershipDeclaration>> fetchPendingDeclarations() async {
    final rows = await _client
        .from('liderancas')
        .select()
        .filter('confirmado_em', 'is', null)
        .filter('rejeitado_em', 'is', null);
    return rows.map(LeadershipDeclaration.fromMap).toList();
  }
}

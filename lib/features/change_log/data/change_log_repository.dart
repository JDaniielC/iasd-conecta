import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/change_log_entry.dart';

/// Leitura de `public.mudancas`. Só leitura: não existe caminho de escrita, nem
/// aqui nem em lugar nenhum do cliente — a tabela não tem policy nem grant de
/// insert/update/delete, e quem escreve são os gatilhos.
class ChangeLogRepository {
  ChangeLogRepository(this._client);

  final SupabaseClient _client;

  /// 20 exibidos + 1 para a tela saber que há mais, sem `count` numa tabela que
  /// só cresce.
  static const pageSize = 20;
  static const _fetchLimit = pageSize + 1;

  Future<List<ChangeLogEntry>> fetchForGroup(String groupId) =>
      _fetch(_client.from('mudancas').select().eq('grupo_id', groupId));

  Future<List<ChangeLogEntry>> fetchForAction(String actionId) =>
      _fetch(_client.from('mudancas').select().eq('acao_id', actionId));

  Future<List<ChangeLogEntry>> _fetch(PostgrestFilterBuilder<dynamic> query) async {
    final rows = await query.order('created_at', ascending: false).limit(_fetchLimit)
        as List;
    final linhas = rows.cast<Map<String, dynamic>>();

    // Um RPC `perfil_publico` por AUTOR DISTINTO, não por linha: numa lista de
    // 21 eventos as mesmas duas ou três pessoas se repetem.
    final autores = linhas
        .map((r) => r['autor_id'] as String?)
        .whereType<String>()
        .toSet();
    final nomes = <String, String>{};
    for (final uid in autores) {
      final r = await _client.rpc('perfil_publico', params: {'p_id': uid}) as List;
      if (r.isNotEmpty) {
        nomes[uid] = (r.first as Map<String, dynamic>)['nome_exibido'] as String;
      }
    }

    // `fromMap` devolve nulo para tipo que este build não conhece. Ignorar a
    // linha é deliberado: a migration vai antes do build web, então por alguns
    // minutos o banco pode ter um tipo que o app ainda não desenha, e sumir com
    // a tela inteira por causa disso seria pior.
    return [
      for (final row in linhas)
        ?ChangeLogEntry.fromMap(row,
            authorName: nomes[row['autor_id'] as String?]),
    ];
  }
}

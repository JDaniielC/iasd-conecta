import 'package:postgres/postgres.dart';

/// Ferramentas dos testes da change `log-de-mudancas-em-grupo-e-acao`.
///
/// Sessões (`asUser`, `asVisitor`) e montagem de Grupo/Rodada/Ação vêm de
/// `acao_restrita_helper.dart`.

/// Contagem por tipo, lida como `postgres` — o estado real, não o que a sessão
/// enxerga.
Future<Map<String, int>> tiposDoGrupo(Connection conn, String groupId) async {
  final r = await conn.execute(
    Sql.named(
      'select tipo, count(*) from public.mudancas where grupo_id = @g group by tipo',
    ),
    parameters: {'g': groupId},
  );
  return {
    for (final row in r)
      row.toColumnMap()['tipo'] as String: row.toColumnMap()['count'] as int
  };
}

Future<Map<String, int>> tiposDaAcao(Connection conn, String actionId) async {
  final r = await conn.execute(
    Sql.named(
      'select tipo, count(*) from public.mudancas where acao_id = @a group by tipo',
    ),
    parameters: {'a': actionId},
  );
  return {
    for (final row in r)
      row.toColumnMap()['tipo'] as String: row.toColumnMap()['count'] as int
  };
}

/// Quantos registros a sessão CORRENTE enxerga para uma Ação.
Future<int> visiveisDaAcao(Connection conn, String actionId) async {
  final r = await conn.execute(
    Sql.named('select count(*) from public.mudancas where acao_id = @a'),
    parameters: {'a': actionId},
  );
  return r.first[0]! as int;
}

/// Quantos registros a sessão CORRENTE enxerga para um Grupo, sem Ação.
Future<int> visiveisDoGrupoSemAcao(Connection conn, String groupId) async {
  final r = await conn.execute(
    Sql.named(
      'select count(*) from public.mudancas where grupo_id = @g and acao_id is null',
    ),
    parameters: {'g': groupId},
  );
  return r.first[0]! as int;
}

Future<void> limparMudancasDoGrupo(Connection conn, String groupId) async {
  await conn.execute(
    Sql.named('delete from public.mudancas where grupo_id = @g'),
    parameters: {'g': groupId},
  );
}

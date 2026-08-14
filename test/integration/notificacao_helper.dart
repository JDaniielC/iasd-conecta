import 'package:postgres/postgres.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';

/// Ferramentas dos testes da change `notificacoes-in-app`.
/// Sessões vêm de `acao_restrita_helper.dart`.

/// Avisos que a sessão CORRENTE enxerga na tabela crua.
Future<List<Map<String, dynamic>>> notificacoesVisiveis(Connection conn) async {
  final r = await conn.execute(
    'select destinatario_id::text, tipo, ator_id::text, lida_em '
    'from public.notificacoes order by created_at',
  );
  return r.map((x) => x.toColumnMap()).toList();
}

/// Avisos que a sessão CORRENTE enxerga pela view — o caminho que o app usa.
Future<List<Map<String, dynamic>>> notificacoesAtivas(Connection conn) async {
  final r = await conn.execute(
    'select destinatario_id::text, tipo, acao_id::text '
    'from public.notificacoes_ativas order by created_at',
  );
  return r.map((x) => x.toColumnMap()).toList();
}

/// Contagem por tipo de quem recebeu, lida como `postgres` — o estado real.
Future<Map<String, int>> tiposDe(Connection conn, String destinatarioId) async {
  final r = await conn.execute(
    Sql.named(
      'select tipo, count(*) from public.notificacoes '
      'where destinatario_id = @d group by tipo',
    ),
    parameters: {'d': destinatarioId},
  );
  return {
    for (final row in r)
      row.toColumnMap()['tipo'] as String: row.toColumnMap()['count'] as int
  };
}

Future<void> limparNotificacoes(Connection conn, List<String> uids) async {
  await conn.execute(
    Sql.named(
      'delete from public.notificacoes where destinatario_id = any(@u::uuid[]) '
      'or ator_id = any(@u::uuid[])',
    ),
    parameters: {'u': uids},
  );
}

/// Cenário mínimo de convite: um Grupo, uma Ação avulsa, e as pessoas dentro do
/// Grupo. O convite não exige que a Ação seja do Grupo — o Grupo é a fonte dos
/// contatos, não a dona da Ação.
///
/// Monta chamando os helpers que já existem, e não SQL cru: `createGroup` e
/// `joinGroup` de `acao_restrita_helper.dart`, `createActionWithCapacity` e
/// `createLooseAction` de `convite_helper.dart`. Repetir os `insert` aqui seria
/// a primeira cópia a divergir deles.
Future<({String grupo, String acao})> montarCenarioDeConvite(
  Connection conn, {
  required String donoId,
  required List<String> membros,
  int? limiteVagas,
}) async {
  final grupo =
      await createGroup(conn, ownerId: donoId, name: 'Grupo de convite');
  for (final m in membros) {
    await joinGroup(conn, grupo, m);
  }
  final acao = limiteVagas == null
      ? await createLooseAction(conn, creatorId: donoId, name: 'Ação de convite')
      : await createActionWithCapacity(conn,
          creatorId: donoId, capacity: limiteVagas, name: 'Ação de convite');
  return (grupo: grupo, acao: acao);
}

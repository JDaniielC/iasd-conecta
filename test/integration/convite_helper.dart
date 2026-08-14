import 'package:postgres/postgres.dart';

/// Ferramentas dos testes da change `convite-para-acao`.
///
/// As sessões (`asUser`, `asVisitor`) vêm de `acao_restrita_helper.dart` — são
/// genéricas e já provadas; duplicá-las aqui criaria a segunda cópia que
/// diverge da primeira.

/// Chama `contatos_para_convite` e devolve as linhas cruas.
Future<List<Map<String, dynamic>>> contatosParaConvite(
  Connection conn,
  String actionId,
) async {
  final r = await conn.execute(
    Sql.named('select * from public.contatos_para_convite(@a)'),
    parameters: {'a': actionId},
  );
  return r.map((row) => row.toColumnMap()).toList();
}

/// Chama `convidar_para_acao` e devolve `usuario_id -> resultado`.
Future<Map<String, String>> convidarParaAcao(
  Connection conn, {
  required String actionId,
  required String groupId,
  required List<String> invitees,
}) async {
  final r = await conn.execute(
    Sql.named(
      'select usuario_id::text, resultado '
      'from public.convidar_para_acao(@a, @g, @c::uuid[])',
    ),
    parameters: {'a': actionId, 'g': groupId, 'c': invitees},
  );
  return {
    for (final row in r)
      row.toColumnMap()['usuario_id'] as String:
          row.toColumnMap()['resultado'] as String,
  };
}

/// Convites gravados para uma Ação, lidos como `postgres` (sem RLS) — para o
/// teste conferir o estado real, não o que a sessão enxerga.
Future<List<Map<String, dynamic>>> convitesGravados(
  Connection conn,
  String actionId,
) async {
  final r = await conn.execute(
    Sql.named(
      'select convidado_id::text, grupo_id::text, convidante_id::text, recusado_em '
      'from public.convites_acao where acao_id = @a order by grupo_id',
    ),
    parameters: {'a': actionId},
  );
  return r.map((row) => row.toColumnMap()).toList();
}

/// Cria uma Ação avulsa com limite de vagas — o convite não depende de a Ação
/// ser de Grupo, o Grupo é a fonte dos contatos, não a dona da Ação.
Future<String> createActionWithCapacity(
  Connection conn, {
  required String creatorId,
  required int capacity,
  String name = 'Ação com vaga contada',
}) async {
  final r = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas) "
      "values (@nome, now() + interval '5 days', 'Sede', @criador, @vagas) returning id",
    ),
    parameters: {'nome': name, 'criador': creatorId, 'vagas': capacity},
  );
  return r.single.toColumnMap()['id']! as String;
}

/// Arquiva um Grupo direto no banco (o RPC exige sessão de Dono).
Future<void> arquivarGrupoDireto(Connection conn, String groupId) async {
  await conn.execute(
    Sql.named('update public.grupos set arquivado_em = now() where id = @g'),
    parameters: {'g': groupId},
  );
}

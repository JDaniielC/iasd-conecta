import 'package:postgres/postgres.dart';

/// Ferramentas comuns aos testes da change `acao-direcionada-a-grupo`.
///
/// Todos eles provam a mesma coisa por ângulos diferentes: a restrição vive na
/// policy do banco, não no filtro da tela. Por isso nenhum deles pode rodar
/// como `postgres` — que é dono das tabelas e ignora RLS, provando exatamente
/// nada. Daí [asUser] e [asVisitor] existirem aqui em vez de copiados em oito
/// arquivos.

/// Executa [action] com a identidade de [uid], como o PostgREST faria.
Future<T> asUser<T>(
  Connection conn,
  String uid,
  Future<T> Function() action,
) async {
  await conn.execute('set role authenticated');
  await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    return await action();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

/// Executa [action] como Visitante sem cadastro nenhum.
Future<T> asVisitor<T>(Connection conn, Future<T> Function() action) async {
  await conn.execute('set role anon');
  try {
    return await action();
  } finally {
    await conn.execute('reset role');
  }
}

/// Cria um Grupo com [ownerId] de Dono. O Dono entra em `participacoes_grupo`
/// pelo gatilho da feature 003, então não é semeado aqui.
Future<String> createGroup(
  Connection conn, {
  required String ownerId,
  String name = 'Grupo da change acao-direcionada-a-grupo',
}) async {
  final r = await conn.execute(
    Sql.named(
      "insert into public.grupos (nome, categoria, dono_id) "
      "values (@nome, 'Estudo bíblico', @owner) returning id",
    ),
    parameters: {'nome': name, 'owner': ownerId},
  );
  return r.single.toColumnMap()['id']! as String;
}

Future<void> joinGroup(Connection conn, String groupId, String uid) async {
  await conn.execute(
    Sql.named(
      'insert into public.participacoes_grupo (grupo_id, usuario_id) '
      'values (@g, @u) on conflict do nothing',
    ),
    parameters: {'g': groupId, 'u': uid},
  );
}

/// Abre uma Rodada de votação do Grupo.
///
/// Roda com a identidade de [openedBy] porque
/// `rodadas_votacao_checar_participante` cobra `auth.uid()`, não
/// `new.aberta_por` — como `postgres` sem sessão, `auth.uid()` é nulo e o
/// gatilho recusa com "só participantes do grupo abrem rodada de votação".
Future<String> createVotingRound(
  Connection conn, {
  required String groupId,
  required String openedBy,
}) async {
  return asUser(conn, openedBy, () async {
    final r = await conn.execute(
      Sql.named(
        "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
        "values (@g, @u, now() + interval '1 day') returning id",
      ),
      parameters: {'g': groupId, 'u': openedBy},
    );
    return r.single.toColumnMap()['id']! as String;
  });
}

/// Cria uma Ação **avulsa** — sem Grupo. É a única forma que
/// `create_action_page.dart` conhece.
Future<String> createLooseAction(
  Connection conn, {
  required String creatorId,
  String name = 'Ação avulsa de teste',
  String interval = "interval '5 days'",
}) async {
  final r = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id) "
      "values (@nome, now() + $interval, 'Sede', @criador) returning id",
    ),
    parameters: {'nome': name, 'criador': creatorId},
  );
  return r.single.toColumnMap()['id']! as String;
}

/// Cria uma Ação **de Grupo**, que neste app significa candidata de Rodada.
///
/// Não existe outro caminho: `acoes_candidata_checar_regras` recusa `grupo_id`
/// sem `rodada_id` ("Ação de Grupo só pode ser criada como candidata de uma
/// Rodada de votação") e, com Rodada, deriva o Grupo dela e força
/// `confirmada := false`. Por isso `grupo_id` NÃO é passado aqui — mandá-lo
/// seria escrever um valor que o gatilho sobrescreve.
///
/// A Ação que vence a Rodada é esta mesma linha, com `confirmada = true`, então
/// `restrita_ao_grupo` marcado aqui vale para a candidata e para a vencedora.
Future<String> createGroupAction(
  Connection conn, {
  required String creatorId,
  required String roundId,
  bool restricted = false,
  String name = 'Ação de Grupo de teste',
  String interval = "interval '5 days'",
}) async {
  final r = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id, "
      "restrita_ao_grupo) values (@nome, now() + $interval, 'Sede', @criador, "
      "@rodada, @restrita) returning id",
    ),
    parameters: {
      'nome': name,
      'criador': creatorId,
      'rodada': roundId,
      'restrita': restricted,
    },
  );
  return r.single.toColumnMap()['id']! as String;
}

/// Marca a Ação como vencedora da Rodada, que é o que a torna a Ação de Grupo
/// que fica no feed (`confirmada = true`).
Future<void> makeWinner(Connection conn, String roundId, String actionId) async {
  await conn.execute("set app.bypass_acoes_protecao to 'true'");
  await conn.execute(
    Sql.named('update public.acoes set confirmada = true where id = @a'),
    parameters: {'a': actionId},
  );
  await conn.execute('reset app.bypass_acoes_protecao');
  await conn.execute(
    Sql.named(
      'update public.rodadas_votacao set vencedora_id = @a, fechada_em = now() '
      'where id = @r',
    ),
    parameters: {'a': actionId, 'r': roundId},
  );
}

/// Quantas Ações a identidade corrente enxerga com aquele id.
Future<int> visibleActionCount(Connection conn, String actionId) async {
  final r = await conn.execute(
    Sql.named('select count(*) from public.acoes where id = @id'),
    parameters: {'id': actionId},
  );
  return r.first[0]! as int;
}

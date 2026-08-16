import 'package:postgres/postgres.dart';

/// Ferramentas dos testes da change `chat-de-grupo-e-acao`.
///
/// Sessões e montagem de Grupo/Rodada/Ação vêm de `acao_restrita_helper.dart` —
/// duplicá-las aqui criaria a cópia que diverge.
///
/// Perfil de menor de idade precisa de **apelido**: `apelido_obrigatorio_menor`
/// (feature 015) recusa a linha sem ele. Descoberto na primeira fumaça desta
/// change, e é por isso que [createTestProfileWithAge] existe em vez de um
/// parâmetro solto em `createTestProfile`.
Future<void> createTestProfileWithAge(
  Connection conn,
  String id, {
  required String name,
  required int age,
}) async {
  await conn.execute(
    Sql.named(
      "insert into auth.users (id, aud, role, instance_id) "
      "values (@id, 'authenticated', 'authenticated', "
      "'00000000-0000-0000-0000-000000000000') on conflict (id) do nothing",
    ),
    parameters: {'id': id},
  );
  await conn.execute(
    Sql.named(
      "insert into public.perfis (id, nome, apelido, genero, idade, "
      "consentimento_lgpd_aceito_em) values (@id, @nome, @apelido, 'feminino', "
      "@idade, now()) on conflict (id) do nothing",
    ),
    parameters: {
      'id': id,
      'nome': name,
      'apelido': age < 18 ? name.split(' ').first : null,
      'idade': age,
    },
  );
}

/// `maior_de_idade()` pela sessão corrente.
Future<bool> isOfAge(Connection conn) async {
  final r = await conn.execute('select public.maior_de_idade()');
  return r.first[0]! as bool;
}

/// `pode_ver_chat_grupo(uuid)` pela sessão corrente, chamada DIRETO.
///
/// Direto e não por `select from mensagens`: a função e a policy que a chama
/// são duas barreiras, e um teste que só olha a contagem de mensagens não
/// distingue "a função disse não" de "a policy nem chamou a função".
Future<bool> canSeeGroupChat(Connection conn, String groupId) async {
  final r = await conn.execute(
    Sql.named('select public.pode_ver_chat_grupo(@g)'),
    parameters: {'g': groupId},
  );
  return r.first[0]! as bool;
}

/// `pode_ver_chat_acao(uuid)` pela sessão corrente, chamada DIRETO.
Future<bool> canSeeActionChat(Connection conn, String actionId) async {
  final r = await conn.execute(
    Sql.named('select public.pode_ver_chat_acao(@a)'),
    parameters: {'a': actionId},
  );
  return r.first[0]! as bool;
}

/// Quantas mensagens a sessão CORRENTE enxerga naquele espaço.
Future<int> visibleMessageCount(
  Connection conn, {
  String? groupId,
  String? actionId,
}) async {
  final r = await conn.execute(
    Sql.named(
      'select count(*) from public.mensagens '
      'where ${groupId != null ? 'grupo_id = @id' : 'acao_id = @id'}',
    ),
    parameters: {'id': groupId ?? actionId},
  );
  return r.first[0]! as int;
}

/// Escreve pela sessão corrente. Devolve o id, ou lança se a policy recusar.
Future<String> writeMessage(
  Connection conn, {
  required String authorId,
  String? groupId,
  String? actionId,
  String text = 'quem leva o som?',
}) async {
  final r = await conn.execute(
    Sql.named(
      'insert into public.mensagens (grupo_id, acao_id, autor_id, texto) '
      'values (@g, @a, @autor, @t) returning id',
    ),
    parameters: {'g': groupId, 'a': actionId, 'autor': authorId, 't': text},
  );
  return r.single.toColumnMap()['id']! as String;
}

/// Semeia uma mensagem como `postgres`, sem passar por policy — para montar
/// cenário sem que a montagem já seja o teste.
Future<String> seedMessage(
  Connection conn, {
  required String authorId,
  String? groupId,
  String? actionId,
  String text = 'mensagem semeada',
}) => writeMessage(
  conn,
  authorId: authorId,
  groupId: groupId,
  actionId: actionId,
  text: text,
);

/// Estado de uma mensagem, lido como `postgres` — o real, não o que a sessão vê.
Future<({bool hasText, bool removed})> messageStateOf(
  Connection conn,
  String messageId,
) async {
  final r = await conn.execute(
    Sql.named('select texto, removida_em from public.mensagens where id = @m'),
    parameters: {'m': messageId},
  );
  final row = r.single.toColumnMap();
  return (hasText: row['texto'] != null, removed: row['removida_em'] != null);
}

Future<void> clearGroupChat(Connection conn, String groupId) async {
  await conn.execute(
    Sql.named(
      'delete from public.denuncias_mensagem where mensagem_id in '
      '(select id from public.mensagens where grupo_id = @g)',
    ),
    parameters: {'g': groupId},
  );
  await conn.execute(
    Sql.named('delete from public.mensagens where grupo_id = @g'),
    parameters: {'g': groupId},
  );
}

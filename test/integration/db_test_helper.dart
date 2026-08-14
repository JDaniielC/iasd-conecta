import 'package:postgres/postgres.dart';

/// Conexão direta com o Postgres local do Supabase (`supabase start`), pra
/// testar constraints/RLS/funções do schema sem depender de widget tree nem
/// de dispositivo/emulador — ver research.md "Regras de domínio testadas".
Future<Connection> openTestConnection() {
  return Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: 54322,
      database: 'postgres',
      username: 'postgres',
      password: 'postgres',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
}

/// Cria um `auth.users` mínimo pra servir de dono de um Perfil de teste.
Future<String> createTestUser(Connection conn, String id) async {
  await conn.execute(
    Sql.named(
      "insert into auth.users (id, aud, role, instance_id) "
      "values (@id, 'authenticated', 'authenticated', "
      "'00000000-0000-0000-0000-000000000000') "
      "on conflict (id) do nothing",
    ),
    parameters: {'id': id},
  );
  return id;
}

/// Apaga o Usuário de teste — `perfis` primeiro, `auth.users` depois.
///
/// A ordem e a primeira linha existem desde a feature 009: a FK
/// `perfis.id -> auth.users` era `on delete cascade` e apagar o login levava o
/// Perfil junto. Ela foi derrubada para que o Perfil anonimizado sobreviva ao
/// fim do login, então nada mais cascateia e o `perfis` de teste precisa ser
/// apagado explicitamente — senão ele vaza entre execuções e o próximo insert
/// colide na chave primária.
Future<void> cleanUpTestUser(Connection conn, String id) async {
  await conn.execute(
    Sql.named('delete from public.perfis where id = @id'),
    parameters: {'id': id},
  );
  await conn.execute(
    Sql.named('delete from auth.users where id = @id'),
    parameters: {'id': id},
  );
}

/// Cria `auth.users` + `perfis` (feature 001) pra servir de Usuário de teste
/// em outras features (ex.: `dono_id`/`usuario_id` de Grupo). `auth.users`
/// tem `is_anonymous default false` — este helper já cria um Usuário com
/// Conta (a maioria dos testes de outras features quer isso).
Future<void> createTestProfile(
  Connection conn,
  String id, {
  String name = 'Usuário de Teste',
  String gender = 'feminino',
}) async {
  await createTestUser(conn, id);
  await conn.execute(
    Sql.named(
      "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
      "values (@id, @nome, @genero, 30, now()) on conflict (id) do nothing",
    ),
    parameters: {'id': id, 'nome': name, 'genero': gender},
  );
}

/// Semeia um Administrador do distrito direto no banco, desabilitando o
/// trigger de checagem temporariamente — mesmo mecanismo de bootstrap do
/// primeiro admin descrito em `specs/005-administrador-distrito/quickstart.md`
/// (RLS bypass de superusuário não pula trigger, então precisa disable/enable).
/// Cria um Administrador do distrito de teste, contornando o trigger de regras.
///
/// Tudo numa transação: `alter table ... disable trigger` é GLOBAL e toma
/// ACCESS EXCLUSIVE. Fora de transação, o gatilho fica desligado para todo
/// mundo durante a janela — e `dart test` roda os arquivos em paralelo, então
/// dois testes chamando este helper ao mesmo tempo se atropelam (um religa o
/// gatilho enquanto o outro ainda precisa dele desligado). Dentro da transação
/// o lock é segurado até o commit e os chamadores entram em fila.
Future<void> createTestDistrictAdmin(Connection conn, String userId) async {
  // SERIALIZAÇÃO DO ESTADO GLOBAL — ler antes de remover.
  //
  // `administradores_distrito` é global, e `excluir_minha_conta` decide pela
  // CONTAGEM de administradores: quem é o único não sai. `account_deletion_test`
  // prova isso criando um Administrador e esperando a recusa. Com um
  // Administrador de OUTRO arquivo vivo ao mesmo tempo, aquele deixa de ser o
  // único, a exclusão passa, e o teste falha sem ter feito nada de errado —
  // medido de forma determinística em 2026-08-13, 5 falhas em toda execução.
  //
  // Dezessete arquivos tocam essa tabela. O lock consultivo faz o Postgres
  // serializá-los entre si, e ele é de SESSÃO: some sozinho quando a conexão
  // fecha no `tearDownAll`, então nenhum arquivo precisa lembrar de soltar — e
  // um arquivo que morra no meio não trava a suíte.
  //
  // Por que não `concurrency: 1` no `dart_test.yaml`: aquilo é configuração do
  // runner e não aceita recorte por tag, então serializaria a suíte inteira. O
  // lock serializa só quem disputa o recurso.
  //
  // Isto NÃO é `skip` nem `retry` — a change `estabilizar-suite-de-integracao`
  // proíbe os dois, e com razão: eles apagam o sinal. Aqui o sinal continua; o
  // que muda é que o recurso disputado passou a ser declarado.
  await conn.execute('select pg_advisory_lock(hashtext(\'administradores_distrito\'))');

  await conn.execute('begin');
  await conn.execute(
    'alter table public.administradores_distrito '
    'disable trigger administradores_distrito_checar_regras_trigger',
  );
  await conn.execute(
    Sql.named(
      'insert into public.administradores_distrito (usuario_id, promovido_por) '
      'values (@id, @id) on conflict (usuario_id) do nothing',
    ),
    parameters: {'id': userId},
  );
  await conn.execute(
    'alter table public.administradores_distrito '
    'enable trigger administradores_distrito_checar_regras_trigger',
  );
  await conn.execute('commit');
}

/// Igual [createTestProfile], mas o Usuário é só Perfil — `is_anonymous =
/// true` (nunca fez upgrade pra Conta). Usado pra testar regras que exigem
/// Conta (feature 005: FR-002).
Future<void> createTestProfileWithoutAccount(
  Connection conn,
  String id, {
  String name = 'Usuário sem Conta de Teste',
}) async {
  await conn.execute(
    Sql.named(
      "insert into auth.users (id, aud, role, instance_id, is_anonymous) "
      "values (@id, 'authenticated', 'authenticated', "
      "'00000000-0000-0000-0000-000000000000', true) "
      "on conflict (id) do nothing",
    ),
    parameters: {'id': id},
  );
  await conn.execute(
    Sql.named(
      "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
      "values (@id, @nome, 'feminino', 25, now()) on conflict (id) do nothing",
    ),
    parameters: {'id': id, 'nome': name},
  );
}

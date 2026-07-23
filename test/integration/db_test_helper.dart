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
Future<String> criarUsuarioDeTeste(Connection conn, String id) async {
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

Future<void> limparUsuarioDeTeste(Connection conn, String id) async {
  await conn.execute(
    Sql.named('delete from auth.users where id = @id'),
    parameters: {'id': id},
  );
}

/// Cria `auth.users` + `perfis` (feature 001) pra servir de Usuário de teste
/// em outras features (ex.: `dono_id`/`usuario_id` de Grupo).
Future<void> criarPerfilDeTeste(
  Connection conn,
  String id, {
  String nome = 'Usuário de Teste',
}) async {
  await criarUsuarioDeTeste(conn, id);
  await conn.execute(
    Sql.named(
      "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
      "values (@id, @nome, 'feminino', 30, now()) on conflict (id) do nothing",
    ),
    parameters: {'id': id, 'nome': nome},
  );
}

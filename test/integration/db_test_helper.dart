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

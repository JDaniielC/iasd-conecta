import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '60000000-0000-0000-0000-000000000010';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => createTestProfile(conn, _uidCreator, name: 'Criador ExigeGenero'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidCreator},
    );
    await cleanUpTestUser(conn, _uidCreator);
  });

  test('FR-002: eh_dupla_missionaria=true sem genero_visitado viola o CHECK', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, eh_dupla_missionaria) "
          "values ('Visita', now() + interval '1 day', 'Casa', @criador, 2, true)",
        ),
        parameters: {'criador': _uidCreator},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('Dupla Missionária com genero_visitado preenchido é aceita', () async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, eh_dupla_missionaria, genero_visitado) "
        "values ('Visita', now() + interval '1 day', 'Casa', @criador, 2, true, 'masculino') "
        "returning genero_visitado",
      ),
      parameters: {'criador': _uidCreator},
    );
    expect(rows.single.toColumnMap()['genero_visitado'], 'masculino');
  });
}

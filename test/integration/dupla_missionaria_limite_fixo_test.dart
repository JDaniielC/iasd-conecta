import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '60000000-0000-0000-0000-000000000011';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarPerfilDeTeste(conn, _uidCriador, nome: 'Criador LimiteFixo'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidCriador},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
  });

  test('FR-003: eh_dupla_missionaria=true com limite_vagas != 2 viola o CHECK', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, eh_dupla_missionaria, genero_visitado) "
          "values ('Visita', now() + interval '1 day', 'Casa', @criador, 5, true, 'masculino')",
        ),
        parameters: {'criador': _uidCriador},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('eh_dupla_missionaria=true sem limite_vagas (null) também viola o CHECK', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, eh_dupla_missionaria, genero_visitado) "
          "values ('Visita', now() + interval '1 day', 'Casa', @criador, true, 'masculino')",
        ),
        parameters: {'criador': _uidCriador},
      ),
      throwsA(isA<ServerException>()),
    );
  });
}

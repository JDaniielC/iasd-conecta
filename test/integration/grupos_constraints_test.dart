import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarPerfilDeTeste(conn, _uidDono, name: 'Dono de Teste'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidDono},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
  });

  test('FR-001: insert em grupos com nome em branco falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.grupos (nome, categoria, horario, local, dono_id) "
          "values ('   ', 'Ministério Jovem', 'sábados 16h', 'Sede', @dono)",
        ),
        parameters: {'dono': _uidDono},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('grupo válido (sem detalhes/igreja) é aceito', () async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('SevenBikers', 'Ministério Jovem', 'sábados 6h', 'Praça', @dono) "
        "returning nome",
      ),
      parameters: {'dono': _uidDono},
    );
    expect(rows.single.toColumnMap()['nome'], 'SevenBikers');
  });
}

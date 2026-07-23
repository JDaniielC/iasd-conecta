import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidMenor = '10000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarUsuarioDeTeste(conn, _uidMenor));
  tearDown(() => limparUsuarioDeTeste(conn, _uidMenor));

  test('FR-005: menor de idade sem apelido viola apelido_obrigatorio_menor', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.perfis "
          "(id, nome, genero, idade, consentimento_lgpd_aceito_em) "
          "values (@id, 'Maria Silva', 'feminino', 15, now())",
        ),
        parameters: {'id': _uidMenor},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-005: menor de idade com apelido é aceito', () async {
    await conn.execute(
      Sql.named(
        "insert into public.perfis "
        "(id, nome, apelido, genero, idade, consentimento_lgpd_aceito_em) "
        "values (@id, 'Maria Silva', 'Mari', 'feminino', 15, now())",
      ),
      parameters: {'id': _uidMenor},
    );

    final rows = await conn.execute(
      Sql.named('select apelido from public.perfis where id = @id'),
      parameters: {'id': _uidMenor},
    );
    expect(rows.single.toColumnMap()['apelido'], 'Mari');
  });
}

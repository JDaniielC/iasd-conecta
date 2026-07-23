import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uid = '10000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarUsuarioDeTeste(conn, _uid));
  tearDown(() => limparUsuarioDeTeste(conn, _uid));

  test('FR-003: insert em perfis sem consentimento LGPD falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.perfis (id, nome, genero, idade) "
          "values (@id, 'Ana Souza', 'feminino', 30)",
        ),
        parameters: {'id': _uid},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('cadastro válido (adulto, sem Igreja/telefone) é aceito', () async {
    await conn.execute(
      Sql.named(
        "insert into public.perfis "
        "(id, nome, genero, idade, consentimento_lgpd_aceito_em) "
        "values (@id, 'Ana Souza', 'feminino', 30, now())",
      ),
      parameters: {'id': _uid},
    );

    final rows = await conn.execute(
      Sql.named('select nome from public.perfis where id = @id'),
      parameters: {'id': _uid},
    );
    expect(rows.single.toColumnMap()['nome'], 'Ana Souza');
  });
}

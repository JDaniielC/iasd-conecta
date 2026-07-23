import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidMenor = '10000000-0000-0000-0000-000000000003';
const _uidAdulto = '10000000-0000-0000-0000-000000000004';
const _uidOutro = '10000000-0000-0000-0000-000000000005';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarUsuarioDeTeste(conn, _uidMenor);
    await criarUsuarioDeTeste(conn, _uidAdulto);
    await criarUsuarioDeTeste(conn, _uidOutro);

    await conn.execute(
      Sql.named(
        "insert into public.perfis "
        "(id, nome, apelido, genero, idade, consentimento_lgpd_aceito_em) "
        "values (@id, 'Maria Silva', 'Mari', 'feminino', 15, now())",
      ),
      parameters: {'id': _uidMenor},
    );
    await conn.execute(
      Sql.named(
        "insert into public.perfis "
        "(id, nome, genero, idade, consentimento_lgpd_aceito_em) "
        "values (@id, 'Ana Souza', 'feminino', 30, now())",
      ),
      parameters: {'id': _uidAdulto},
    );
  });

  tearDownAll(() async {
    await limparUsuarioDeTeste(conn, _uidMenor);
    await limparUsuarioDeTeste(conn, _uidAdulto);
    await limparUsuarioDeTeste(conn, _uidOutro);
    await conn.close();
  });

  test('FR-006/SC-002: perfil_publico de menor devolve o apelido', () async {
    final rows = await conn.execute(
      Sql.named('select * from public.perfil_publico(@id)'),
      parameters: {'id': _uidMenor},
    );
    final row = rows.single.toColumnMap();
    expect(row['nome_exibido'], 'Mari');
    expect(row.containsKey('idade'), isFalse);
  });

  test('FR-006: perfil_publico de adulto devolve o próprio nome', () async {
    final rows = await conn.execute(
      Sql.named('select * from public.perfil_publico(@id)'),
      parameters: {'id': _uidAdulto},
    );
    expect(rows.single.toColumnMap()['nome_exibido'], 'Ana Souza');
  });

  test('SC-003: select direto de outro usuário não vaza idade (RLS)', () async {
    await conn.execute("set role authenticated");
    await conn.execute(
      Sql.named(
        "set request.jwt.claims to '{\"sub\":\"@id\",\"role\":\"authenticated\"}'"
            .replaceFirst('@id', _uidOutro),
      ),
    );
    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.perfis where id = @id'),
      parameters: {'id': _uidMenor},
    );
    expect(rows.single.toColumnMap()['total'], 0);
    await conn.execute('reset role');
  });
}

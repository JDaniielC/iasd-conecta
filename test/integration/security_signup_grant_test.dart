import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uid = '95000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestUser(conn, _uid);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.perfis where id = @id'),
      parameters: {'id': _uid},
    );
    await cleanUpTestUser(conn, _uid);
    await conn.close();
  });

  test(
    'BUG DE SEGURANÇA (corrigido): cadastro real como role authenticated não falha por '
    'falta de GRANT em palavras_bloqueadas',
    () async {
      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uid\",\"role\":\"authenticated\"}'",
      );
      try {
        await conn.execute(
          Sql.named(
            "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
            "values (@id, 'Teste Real Signup', 'masculino', 30, now())",
          ),
          parameters: {'id': _uid},
        );
      } finally {
        await conn.execute('reset role');
        await conn.execute('reset request.jwt.claims');
      }

      final rows = await conn.execute(
        Sql.named('select nome from public.perfis where id = @id'),
        parameters: {'id': _uid},
      );
      expect(rows.single.toColumnMap()['nome'], 'Teste Real Signup');
    },
  );
}

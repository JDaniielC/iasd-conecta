import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidLider = '90000000-0000-0000-0000-000000000050';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidLider, name: 'Lider PublicCurrent');
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipPublicCurrent', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidLider},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
    // Confirmada do ano corrente
    await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        "values (@grupo, @uid, extract(year from now())::int, now(), @uid)",
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    // Confirmada de um ano anterior (mesmo grupo, outro ano — não conta como atual)
    await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        "values (@grupo, @uid, extract(year from now())::int - 1, now(), @uid)",
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.liderancas where grupo_id = @id'),
      parameters: {'id': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': groupId},
    );
    await cleanUpTestUser(conn, _uidLider);
    await conn.close();
  });

  test('FR-006/FR-008: só a confirmada do ano corrente conta como atual', () async {
    final rows = await conn.execute(
      Sql.named(
        'select ano from public.liderancas '
        'where grupo_id = @grupo and confirmado_em is not null and rejeitado_em is null '
        'and ano = extract(year from now())::int',
      ),
      parameters: {'grupo': groupId},
    );
    expect(rows, hasLength(1));
  });

  test('FR-006: visível ao role anon (Visitante sem cadastro)', () async {
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named(
          'select ano from public.liderancas where grupo_id = @grupo and confirmado_em is not null',
        ),
        parameters: {'grupo': groupId},
      );
      expect(rows, hasLength(2));
    } finally {
      await conn.execute('reset role');
    }
  });
}

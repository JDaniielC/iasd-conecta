import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidLider = '90000000-0000-0000-0000-000000000021';

void main() {
  late Connection conn;
  late String groupId;

  Future<void> asUser(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidLider, name: 'Lider DeclareIdempotent');
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipDeclareIdempotent', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidLider},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
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

  test('FR-003: autodeclarar duas vezes pro mesmo Grupo/ano é não-operação', () async {
    await asUser(_uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': groupId},
      );
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': groupId},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.liderancas '
        'where grupo_id = @grupo and usuario_id = @uid and ano = 2026',
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}

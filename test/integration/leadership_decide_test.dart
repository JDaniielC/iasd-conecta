import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000040';
const _uidLider = '90000000-0000-0000-0000-000000000041';

void main() {
  late Connection conn;
  late String groupId;
  late String declarationId;

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
    await createTestProfile(conn, _uidAdmin, name: 'Admin Decide');
    await createTestProfile(conn, _uidLider, name: 'Lider Decide');
    await createTestDistrictAdmin(conn, _uidAdmin);
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipDecide', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidAdmin},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
    final declarationRows = await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano) '
        'values (@grupo, @uid, 2026) returning id',
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    declarationId = declarationRows.single.toColumnMap()['id']! as String;
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
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidAdmin);
    await cleanUpTestUser(conn, _uidLider);
    await conn.close();
  });

  test('FR-004: Administrador confirma e rejeita corretamente', () async {
    await asUser(_uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, true)'),
        parameters: {'id': declarationId},
      );
    });
    var row = (await conn.execute(
      Sql.named(
        'select confirmado_em, confirmado_por, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': declarationId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNotNull);
    expect(row['confirmado_por'], _uidAdmin);
    expect(row['rejeitado_em'], isNull);

    await asUser(_uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, false)'),
        parameters: {'id': declarationId},
      );
    });
    row = (await conn.execute(
      Sql.named(
        'select confirmado_em, confirmado_por, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': declarationId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNull);
    expect(row['confirmado_por'], isNull);
    expect(row['rejeitado_em'], isNotNull);
  });
}

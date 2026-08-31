import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000070';
const _uidLider = '90000000-0000-0000-0000-000000000071';

void main() {
  late Connection conn;
  late String groupId;
  late String declarationId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAdmin, name: 'Admin RedeclareAfterReject');
    await createTestProfile(conn, _uidLider, name: 'Lider RedeclareAfterReject');
    await createTestDistrictAdmin(conn, _uidAdmin);
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipRedeclareAfterReject', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidAdmin},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;

    await asUser(conn, _uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': groupId},
      );
    });
    final row = await conn.execute(
      Sql.named(
        'select id from public.liderancas where grupo_id = @grupo and usuario_id = @uid and ano = 2026',
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    declarationId = row.single.toColumnMap()['id']! as String;

    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, false)'),
        parameters: {'id': declarationId},
      );
    });
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

  test('FR-010: redeclarar depois de rejeitado no mesmo ano volta a ficar pendente', () async {
    var row = (await conn.execute(
      Sql.named('select rejeitado_em from public.liderancas where id = @id'),
      parameters: {'id': declarationId},
    ))
        .single
        .toColumnMap();
    expect(row['rejeitado_em'], isNotNull);

    await asUser(conn, _uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': groupId},
      );
    });

    row = (await conn.execute(
      Sql.named(
        'select confirmado_em, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': declarationId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNull);
    expect(row['rejeitado_em'], isNull);
  });
}

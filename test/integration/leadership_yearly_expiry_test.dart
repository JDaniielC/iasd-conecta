import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidLider = '90000000-0000-0000-0000-000000000060';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidLider, name: 'Lider YearlyExpiry');
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipYearlyExpiry', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidLider},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
    // Confirmada do ano passado — expira preguiçosamente, sem job.
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

  test('FR-008: confirmação de ano anterior não conta como atual', () async {
    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.liderancas '
        'where grupo_id = @grupo and confirmado_em is not null and '
        'ano = extract(year from now())::int',
      ),
      parameters: {'grupo': groupId},
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });

  test('FR-009: mesma pessoa redeclara pro ano corrente com sucesso', () async {
    await asUser(conn, _uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, extract(year from now())::int)'),
        parameters: {'grupo': groupId},
      );
    });
    final rows = await conn.execute(
      Sql.named(
        'select ano, confirmado_em from public.liderancas '
        'where grupo_id = @grupo and usuario_id = @uid and ano = extract(year from now())::int',
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    expect(rows, hasLength(1));
    expect(rows.single.toColumnMap()['confirmado_em'], isNull);
  });
}

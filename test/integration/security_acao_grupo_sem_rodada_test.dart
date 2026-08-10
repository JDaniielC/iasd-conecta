import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAtacante = '95000000-0000-0000-0000-000000000010';
const _uidOwner = '95000000-0000-0000-0000-000000000011';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAtacante, name: 'Atacante SemRodada');
    await createTestProfile(conn, _uidOwner, name: 'Dono SemRodada');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo SemRodada', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @id'),
      parameters: {'id': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': groupId},
    );
    await cleanUpTestUser(conn, _uidAtacante);
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  test(
    'BUG DE SEGURANÇA (corrigido): não dá pra forjar Ação de Grupo confirmada com '
    'grupo_id preenchido e rodada_id nulo, sem nunca ter participado do Grupo',
    () async {
      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uidAtacante\",\"role\":\"authenticated\"}'",
      );
      try {
        await expectLater(
          conn.execute(
            Sql.named(
              "insert into public.acoes (nome, data_hora, local, criador_id, grupo_id) "
              "values ('Forjada', now() + interval '1 day', 'X', @uid, @grupo)",
            ),
            parameters: {'uid': _uidAtacante, 'grupo': groupId},
          ),
          throwsA(isA<ServerException>()),
        );
      } finally {
        await conn.execute('reset role');
        await conn.execute('reset request.jwt.claims');
      }
    },
  );
}

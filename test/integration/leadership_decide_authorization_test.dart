import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '13000000-0000-0000-0000-000000000030';
const _uidComum = '13000000-0000-0000-0000-000000000031';
const _uidLider = '13000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late String groupId;
  late String declarationId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono DecideAuth');
    await createTestProfile(conn, _uidComum, name: 'Comum DecideAuth');
    await createTestProfile(conn, _uidLider, name: 'Lider DecideAuth');
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipDecideAuth', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
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
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidComum);
    await cleanUpTestUser(conn, _uidLider);
    await conn.close();
  });

  test('FR-005: Dono do Grupo não consegue decidir (só Administrador do distrito)', () async {
    await expectLater(
      asUser(conn, _uidOwner, () async {
        await conn.execute(
          Sql.named('select public.decidir_lideranca(@id, true)'),
          parameters: {'id': declarationId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-005: Usuário comum não consegue decidir', () async {
    await expectLater(
      asUser(conn, _uidComum, () async {
        await conn.execute(
          Sql.named('select public.decidir_lideranca(@id, true)'),
          parameters: {'id': declarationId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

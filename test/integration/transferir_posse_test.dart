import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000006';
const _uidNonMember = '40000000-0000-0000-0000-000000000007';
const _uidMember = '40000000-0000-0000-0000-000000000008';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono Transfere');
    await createTestProfile(conn, _uidNonMember, name: 'Fora do Grupo');
    await createTestProfile(conn, _uidMember, name: 'Participante Transfere');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Transfere', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidNonMember);
    await cleanUpTestUser(conn, _uidMember);
    await conn.close();
  });

  test('FR-011: transferir pra quem não participa falha', () async {
    await expectLater(
      conn.execute(
        Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
        parameters: {'novo': _uidNonMember, 'grupo': groupId},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-011: transferir pra quem já participa funciona', () async {
    await conn.execute(
      Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
      parameters: {'novo': _uidMember, 'grupo': groupId},
    );
    final rows = await conn.execute(
      Sql.named('select dono_id from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    expect(rows.single.toColumnMap()['dono_id'], _uidMember);
  });
}

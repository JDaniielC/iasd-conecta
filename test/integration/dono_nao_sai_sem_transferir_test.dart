import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000009';
const _uidMember = '40000000-0000-0000-0000-000000000010';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono Sai');
    await createTestProfile(conn, _uidMember, name: 'Participante Sai');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Sai', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
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
    await cleanUpTestUser(conn, _uidMember);
    await conn.close();
  });

  test('FR-012: Dono não sai do grupo sem transferir a posse antes', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @dono',
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('participante comum (não Dono) sai livremente', () async {
    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @usuario',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );
    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @usuario',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });

  test('Dono sai depois de transferir a posse', () async {
    // recoloca o participante pra poder transferir de novo
    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario) '
        'on conflict (grupo_id, usuario_id) do nothing',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );
    await conn.execute(
      Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
      parameters: {'novo': _uidMember, 'grupo': groupId},
    );

    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @antigo',
      ),
      parameters: {'grupo': groupId, 'antigo': _uidOwner},
    );

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @antigo',
      ),
      parameters: {'grupo': groupId, 'antigo': _uidOwner},
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000011';
const _uidOutro = '40000000-0000-0000-0000-000000000012';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono RLS');
    await createTestProfile(conn, _uidOutro, name: 'Outro RLS');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo RLS', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidOutro);
    await conn.close();
  });

  test('FR-009: quem não é Dono não consegue editar o Grupo', () async {
    await asUser(conn, _uidOutro, () async {
      await conn.execute(
        Sql.named("update public.grupos set nome = 'Hackeado' where id = @grupo"),
        parameters: {'grupo': groupId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select nome from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    expect(rows.single.toColumnMap()['nome'], 'Grupo RLS');
  });

  test('FR-010: quem não é Dono não consegue remover participante', () async {
    await asUser(conn, _uidOutro, () async {
      await conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @dono',
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @dono',
      ),
      parameters: {'grupo': groupId, 'dono': _uidOwner},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });

  test('o Dono consegue editar o próprio Grupo', () async {
    await asUser(conn, _uidOwner, () async {
      await conn.execute(
        Sql.named("update public.grupos set nome = 'Editado pelo Dono' where id = @grupo"),
        parameters: {'grupo': groupId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select nome from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    expect(rows.single.toColumnMap()['nome'], 'Editado pelo Dono');
  });
}

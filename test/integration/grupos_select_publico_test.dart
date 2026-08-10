import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000003';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono Publico');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Público', 'Ministério Jovem', 'sábados 16h', 'Sede', @dono) "
        "returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidOwner},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  test('FR-005: papel anon (Visitante) vê grupos sem sessão', () async {
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named('select nome from public.grupos where id = @id'),
        parameters: {'id': groupId},
      );
      expect(rows.single.toColumnMap()['nome'], 'Grupo Público');
    } finally {
      await conn.execute('reset role');
    }
  });

  test('FR-006: papel anon (Visitante) vê a lista de participantes', () async {
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named('select usuario_id from public.participacoes_grupo where grupo_id = @id'),
        parameters: {'id': groupId},
      );
      expect(rows, isNotEmpty);
    } finally {
      await conn.execute('reset role');
    }
  });

  test('anon não consegue inserir grupo (sem sessão de dono)', () async {
    await conn.execute('set role anon');
    try {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.grupos (nome, categoria, horario, local, dono_id) "
            "values ('Invasor', 'Jovem', '19h', 'Sede', @dono)",
          ),
          parameters: {'dono': _uidOwner},
        ),
        throwsA(isA<ServerException>()),
      );
    } finally {
      await conn.execute('reset role');
    }
  });
}

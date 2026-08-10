import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => createTestProfile(conn, _uidOwner, name: 'Dono Auto'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidOwner},
    );
    await cleanUpTestUser(conn, _uidOwner);
  });

  test(
    'FR-003: criar grupo insere automaticamente participação do dono',
    () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.grupos (nome, categoria, horario, local, dono_id) "
          "values ('Coral', 'Ministério da Música', 'quartas 19h', 'Sede', @dono) "
          "returning id",
        ),
        parameters: {'dono': _uidOwner},
      );
      final groupId = rows.single.toColumnMap()['id'];

      final memberships = await conn.execute(
        Sql.named(
          'select usuario_id from public.participacoes_grupo where grupo_id = @grupo',
        ),
        parameters: {'grupo': groupId},
      );

      expect(memberships, hasLength(1));
      expect(memberships.single.toColumnMap()['usuario_id'], _uidOwner);
    },
  );
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidSemConta = '11000000-0000-0000-0000-000000000020';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfileWithoutAccount(conn, _uidSemConta, name: 'SemConta LeadershipReq');
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipRequiresAccount', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidSemConta},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
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
    await cleanUpTestUser(conn, _uidSemConta);
    await conn.close();
  });

  test('FR-002: usuário só com Perfil (sem Conta) não consegue autodeclarar', () async {
    await expectLater(
      asUser(conn, _uidSemConta, () async {
        await conn.execute(
          Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
          parameters: {'grupo': groupId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

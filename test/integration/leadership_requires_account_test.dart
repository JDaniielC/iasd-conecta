import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidSemConta = '90000000-0000-0000-0000-000000000020';

void main() {
  late Connection conn;
  late String groupId;

  Future<void> comoUsuario(String uid, Future<void> Function() acao) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await acao();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilSemContaDeTeste(conn, _uidSemConta, name: 'SemConta LeadershipReq');
    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipRequiresAccount', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidSemConta},
    );
    groupId = grupoRows.single.toColumnMap()['id']! as String;
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
    await limparUsuarioDeTeste(conn, _uidSemConta);
    await conn.close();
  });

  test('FR-002: usuário só com Perfil (sem Conta) não consegue autodeclarar', () async {
    await expectLater(
      comoUsuario(_uidSemConta, () async {
        await conn.execute(
          Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
          parameters: {'grupo': groupId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

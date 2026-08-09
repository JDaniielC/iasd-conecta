import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '90000000-0000-0000-0000-000000000030';
const _uidComum = '90000000-0000-0000-0000-000000000031';
const _uidLider = '90000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late String groupId;
  late String liderancaId;

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
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono DecideAuth');
    await criarPerfilDeTeste(conn, _uidComum, name: 'Comum DecideAuth');
    await criarPerfilDeTeste(conn, _uidLider, name: 'Lider DecideAuth');
    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipDecideAuth', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = grupoRows.single.toColumnMap()['id']! as String;
    final liderancaRows = await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano) '
        'values (@grupo, @uid, 2026) returning id',
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    liderancaId = liderancaRows.single.toColumnMap()['id']! as String;
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
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidComum);
    await limparUsuarioDeTeste(conn, _uidLider);
    await conn.close();
  });

  test('FR-005: Dono do Grupo não consegue decidir (só Administrador do distrito)', () async {
    await expectLater(
      comoUsuario(_uidDono, () async {
        await conn.execute(
          Sql.named('select public.decidir_lideranca(@id, true)'),
          parameters: {'id': liderancaId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-005: Usuário comum não consegue decidir', () async {
    await expectLater(
      comoUsuario(_uidComum, () async {
        await conn.execute(
          Sql.named('select public.decidir_lideranca(@id, true)'),
          parameters: {'id': liderancaId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

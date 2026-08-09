import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000011';
const _uidOutro = '40000000-0000-0000-0000-000000000012';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono RLS');
    await criarPerfilDeTeste(conn, _uidOutro, name: 'Outro RLS');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo RLS', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidOutro);
    await conn.close();
  });

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
    }
  }

  test('FR-009: quem não é Dono não consegue editar o Grupo', () async {
    await comoUsuario(_uidOutro, () async {
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
    await comoUsuario(_uidOutro, () async {
      await conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @dono',
        ),
        parameters: {'grupo': groupId, 'dono': _uidDono},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @dono',
      ),
      parameters: {'grupo': groupId, 'dono': _uidDono},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });

  test('o Dono consegue editar o próprio Grupo', () async {
    await comoUsuario(_uidDono, () async {
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

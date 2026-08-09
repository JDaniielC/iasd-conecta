import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '80000000-0000-0000-0000-000000000040';

Future<void> _comoUsuario(Connection conn, String uid, Future<void> Function() action) async {
  await conn.execute('set role authenticated');
  await conn.execute("set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await action();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

void main() {
  late Connection conn;
  late String categoriaAId;
  late String categoriaBId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin NomeDuplicado');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);
    final catA = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria DupA') returning id"),
    );
    categoriaAId = catA.single.toColumnMap()['id']! as String;
    final catB = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria DupB') returning id"),
    );
    categoriaBId = catB.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes_sugeridas where categoria_id in (@a, @b)'),
      parameters: {'a': categoriaAId, 'b': categoriaBId},
    );
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id in (@a, @b)'),
      parameters: {'a': categoriaAId, 'b': categoriaBId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-009: mesmo nome em Categorias diferentes é permitido', () async {
    await _comoUsuario(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoriaAId, 'nome': 'Retiro'},
      );
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoriaBId, 'nome': 'Retiro'},
      );
    });

    final rows = await conn.execute(
      Sql.named('select categoria_id from public.acoes_sugeridas where nome = @nome'),
      parameters: {'nome': 'Retiro'},
    );
    expect(rows, hasLength(2));
  });
}

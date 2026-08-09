import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '80000000-0000-0000-0000-000000000010';

Future<void> _comoUsuario(Connection conn, String uid, Future<void> Function() acao) async {
  await conn.execute('set role authenticated');
  await conn.execute("set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await acao();
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
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin JoinCategoria');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);

    final catA = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria JoinA') returning id"),
    );
    categoriaAId = catA.single.toColumnMap()['id']! as String;
    final catB = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria JoinB') returning id"),
    );
    categoriaBId = catB.single.toColumnMap()['id']! as String;

    await _comoUsuario(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoriaAId, 'nome': 'Sugestao A1'},
      );
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoriaBId, 'nome': 'Sugestao B1'},
      );
    });
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

  test('FR-004: sugestões batem só com a categoria pedida', () async {
    final rows = await conn.execute(
      Sql.named(
        'select s.nome from public.acoes_sugeridas s '
        'join public.categorias_grupo c on c.id = s.categoria_id '
        'where c.nome = @nome',
      ),
      parameters: {'nome': 'Categoria JoinA'},
    );
    expect(rows.map((r) => r.toColumnMap()['nome']), ['Sugestao A1']);
  });
}

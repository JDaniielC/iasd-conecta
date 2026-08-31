import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidAdmin = '80000000-0000-0000-0000-000000000040';

void main() {
  late Connection conn;
  late String categoryAId;
  late String categoryBId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAdmin, name: 'Admin NomeDuplicado');
    await createTestDistrictAdmin(conn, _uidAdmin);
    final catA = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria DupA') returning id"),
    );
    categoryAId = catA.single.toColumnMap()['id']! as String;
    final catB = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria DupB') returning id"),
    );
    categoryBId = catB.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes_sugeridas where categoria_id in (@a, @b)'),
      parameters: {'a': categoryAId, 'b': categoryBId},
    );
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id in (@a, @b)'),
      parameters: {'a': categoryAId, 'b': categoryBId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-009: mesmo nome em Categorias diferentes é permitido', () async {
    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoryAId, 'nome': 'Retiro'},
      );
      await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
        parameters: {'cat': categoryBId, 'nome': 'Retiro'},
      );
    });

    final rows = await conn.execute(
      Sql.named('select categoria_id from public.acoes_sugeridas where nome = @nome'),
      parameters: {'nome': 'Retiro'},
    );
    expect(rows, hasLength(2));
  });
}

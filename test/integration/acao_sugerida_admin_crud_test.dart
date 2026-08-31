import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidAdmin = '80000000-0000-0000-0000-000000000030';

void main() {
  late Connection conn;
  late String categoryId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAdmin, name: 'Admin CrudTest');
    await createTestDistrictAdmin(conn, _uidAdmin);
    final cat = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria CrudTest') returning id"),
    );
    categoryId = cat.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes_sugeridas where categoria_id = @id'),
      parameters: {'id': categoryId},
    );
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id = @id'),
      parameters: {'id': categoryId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-001/FR-002: Administrador cadastra e remove; remover não afeta Ação já criada', () async {
    late String sugestaoId;
    await asUser(conn, _uidAdmin, () async {
      final rows = await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome) returning id'),
        parameters: {'cat': categoryId, 'nome': 'Culto Jovem'},
      );
      sugestaoId = rows.single.toColumnMap()['id']! as String;
    });

    await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Culto Jovem', now() + interval '1 day', 'Templo', @criador)",
      ),
      parameters: {'criador': _uidAdmin},
    );

    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('delete from public.acoes_sugeridas where id = @id'),
        parameters: {'id': sugestaoId},
      );
    });

    final sugestaoRows = await conn.execute(
      Sql.named('select id from public.acoes_sugeridas where id = @id'),
      parameters: {'id': sugestaoId},
    );
    expect(sugestaoRows, isEmpty);

    final actionRows = await conn.execute(
      Sql.named("select nome from public.acoes where nome = 'Culto Jovem' and criador_id = @criador"),
      parameters: {'criador': _uidAdmin},
    );
    expect(actionRows, hasLength(1));

    await conn.execute(
      Sql.named("delete from public.acoes where nome = 'Culto Jovem' and criador_id = @criador"),
      parameters: {'criador': _uidAdmin},
    );
  });
}

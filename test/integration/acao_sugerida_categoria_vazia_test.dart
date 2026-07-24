import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

void main() {
  late Connection conn;
  late String categoriaId;

  setUpAll(() async {
    conn = await openTestConnection();
    final cat = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria Vazia Teste') returning id"),
    );
    categoriaId = cat.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id = @id'),
      parameters: {'id': categoriaId},
    );
    await conn.close();
  });

  test('FR-008: categoria sem nenhuma Ação sugerida retorna lista vazia, sem erro', () async {
    final rows = await conn.execute(
      Sql.named('select nome from public.acoes_sugeridas where categoria_id = @id'),
      parameters: {'id': categoriaId},
    );
    expect(rows, isEmpty);
  });
}

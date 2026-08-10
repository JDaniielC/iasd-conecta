import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidComum = '80000000-0000-0000-0000-000000000020';

Future<void> _asUser(Connection conn, String uid, Future<void> Function() action) async {
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
  late String categoryId;
  late String sugestaoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidComum, name: 'Comum Authorization');
    final cat = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria Authorization') returning id"),
    );
    categoryId = cat.single.toColumnMap()['id']! as String;

    final sugestao = await conn.execute(
      Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome) returning id'),
      parameters: {'cat': categoryId, 'nome': 'Ja Existente'},
    );
    sugestaoId = sugestao.single.toColumnMap()['id']! as String;
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
    await cleanUpTestUser(conn, _uidComum);
    await conn.close();
  });

  test('FR-003: usuário comum não consegue cadastrar Ação sugerida', () async {
    await expectLater(
      _asUser(conn, _uidComum, () async {
        await conn.execute(
          Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
          parameters: {'cat': categoryId, 'nome': 'Tentativa Invalida'},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-003: usuário comum não consegue remover Ação sugerida', () async {
    var afetados = -1;
    await _asUser(conn, _uidComum, () async {
      final result = await conn.execute(
        Sql.named('delete from public.acoes_sugeridas where id = @id'),
        parameters: {'id': sugestaoId},
      );
      afetados = result.affectedRows;
    });
    expect(afetados, 0);

    final rows = await conn.execute(
      Sql.named('select id from public.acoes_sugeridas where id = @id'),
      parameters: {'id': sugestaoId},
    );
    expect(rows, hasLength(1));
  });
}

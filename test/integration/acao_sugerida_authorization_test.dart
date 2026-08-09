import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidComum = '80000000-0000-0000-0000-000000000020';

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
  late String categoriaId;
  late String sugestaoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidComum, name: 'Comum Authorization');
    final cat = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria Authorization') returning id"),
    );
    categoriaId = cat.single.toColumnMap()['id']! as String;

    final sugestao = await conn.execute(
      Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome) returning id'),
      parameters: {'cat': categoriaId, 'nome': 'Ja Existente'},
    );
    sugestaoId = sugestao.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes_sugeridas where categoria_id = @id'),
      parameters: {'id': categoriaId},
    );
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id = @id'),
      parameters: {'id': categoriaId},
    );
    await limparUsuarioDeTeste(conn, _uidComum);
    await conn.close();
  });

  test('FR-003: usuário comum não consegue cadastrar Ação sugerida', () async {
    await expectLater(
      _comoUsuario(conn, _uidComum, () async {
        await conn.execute(
          Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome)'),
          parameters: {'cat': categoriaId, 'nome': 'Tentativa Invalida'},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-003: usuário comum não consegue remover Ação sugerida', () async {
    var afetados = -1;
    await _comoUsuario(conn, _uidComum, () async {
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

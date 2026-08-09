import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '80000000-0000-0000-0000-000000000030';

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

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin CrudTest');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);
    final cat = await conn.execute(
      Sql.named("insert into public.categorias_grupo (nome) values ('Categoria CrudTest') returning id"),
    );
    categoriaId = cat.single.toColumnMap()['id']! as String;
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
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-001/FR-002: Administrador cadastra e remove; remover não afeta Ação já criada', () async {
    late String sugestaoId;
    await _comoUsuario(conn, _uidAdmin, () async {
      final rows = await conn.execute(
        Sql.named('insert into public.acoes_sugeridas (categoria_id, nome) values (@cat, @nome) returning id'),
        parameters: {'cat': categoriaId, 'nome': 'Culto Jovem'},
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

    await _comoUsuario(conn, _uidAdmin, () async {
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

    final acaoRows = await conn.execute(
      Sql.named("select nome from public.acoes where nome = 'Culto Jovem' and criador_id = @criador"),
      parameters: {'criador': _uidAdmin},
    );
    expect(acaoRows, hasLength(1));

    await conn.execute(
      Sql.named("delete from public.acoes where nome = 'Culto Jovem' and criador_id = @criador"),
      parameters: {'criador': _uidAdmin},
    );
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — Ação avulsa não pode ser restrita.
///
/// Sem `grupo_id` não há a quem restringir: uma Ação restrita e sem Grupo
/// ficaria invisível para todo mundo, para sempre, inclusive para quem a criou.
/// A tela esconder o controle é conveniência; a garantia é a constraint
/// `acoes_restrita_exige_grupo`, e é ela que este arquivo prova — pela API, que
/// é por onde uma chamada direta chegaria.

const _uidCreator = 'a3000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criadora A3');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @c'),
      parameters: {'c': _uidCreator},
    );
    await cleanUpTestUser(conn, _uidCreator);
    await conn.close();
  });

  test('o banco recusa Ação sem Grupo com a restrição marcada', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, "
          "restrita_ao_grupo) values ('Avulsa restrita A3', "
          "now() + interval '5 days', 'Sede', @c, true)",
        ),
        parameters: {'c': _uidCreator},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('o banco recusa tornar restrita uma Ação avulsa que já existe', () async {
    final id = await createLooseAction(conn, creatorId: _uidCreator, name: 'Avulsa A3');
    await expectLater(
      asUser(
        conn,
        _uidCreator,
        () => conn.execute(
          Sql.named(
              'update public.acoes set restrita_ao_grupo = true where id = @a'),
          parameters: {'a': id},
        ),
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('Ação avulsa com a restrição desmarcada é aceita, como sempre foi',
      () async {
    final id = await createLooseAction(conn, creatorId: _uidCreator, name: 'Avulsa ok A3');
    final r = await conn.execute(
      Sql.named('select restrita_ao_grupo from public.acoes where id = @a'),
      parameters: {'a': id},
    );
    expect(r.single.toColumnMap()['restrita_ao_grupo'], isFalse);
  });
}

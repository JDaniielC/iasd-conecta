import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000022';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador Publico');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Ação Pública', now() + interval '5 days', 'Sede', @criador) returning id",
      ),
      parameters: {'criador': _uidCreator},
    );
    actionId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': actionId},
    );
    await cleanUpTestUser(conn, _uidCreator);
    await conn.close();
  });

  test('FR-010: papel anon (Visitante) vê a Ação sem sessão', () async {
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named('select nome from public.acoes where id = @id'),
        parameters: {'id': actionId},
      );
      expect(rows.single.toColumnMap()['nome'], 'Ação Pública');
    } finally {
      await conn.execute('reset role');
    }
  });

  test('FR-010: papel anon vê a lista de confirmados', () async {
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named('select usuario_id from public.confirmacoes_acao where acao_id = @id'),
        parameters: {'id': actionId},
      );
      expect(rows, isNotEmpty);
    } finally {
      await conn.execute('reset role');
    }
  });

  test('FR-011: anon não consegue confirmar presença', () async {
    await conn.execute('set role anon');
    try {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @criador)",
          ),
          parameters: {'acao': actionId, 'criador': _uidCreator},
        ),
        throwsA(isA<ServerException>()),
      );
    } finally {
      await conn.execute('reset role');
    }
  });
}

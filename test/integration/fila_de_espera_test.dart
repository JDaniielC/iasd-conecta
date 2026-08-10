import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000030';
const _uidSegundo = '50000000-0000-0000-0000-000000000031';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador Fila');
    await createTestProfile(conn, _uidSegundo, name: 'Segundo Fila');

    // limite 1 vaga: criador já ocupa a única vaga (FR-013)
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) "
        "values ('Ação Lotada', now() + interval '5 days', 'Sede', 1, @criador) returning id",
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
    await cleanUpTestUser(conn, _uidSegundo);
    await conn.close();
  });

  test('FR-005: confirmar em Ação lotada vira fila', () async {
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
      ),
      parameters: {'acao': actionId, 'usuario': _uidSegundo},
    );

    final rows = await conn.execute(
      Sql.named(
        'select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @usuario',
      ),
      parameters: {'acao': actionId, 'usuario': _uidSegundo},
    );
    expect(rows.single.toColumnMap()['status'], 'fila');
  });
}

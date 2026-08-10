import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000042';
const _uidOutro = '50000000-0000-0000-0000-000000000043';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador Bloqueia');
    await createTestProfile(conn, _uidOutro, name: 'Outro Bloqueia');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Ação Bloqueia', now() + interval '5 days', 'Sede', @criador) returning id",
      ),
      parameters: {'criador': _uidCreator},
    );
    actionId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
      parameters: {'acao': actionId},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': actionId},
    );
    await cleanUpTestUser(conn, _uidCreator);
    await cleanUpTestUser(conn, _uidOutro);
    await conn.close();
  });

  test('FR-009: confirmar presença numa Ação cancelada falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
        ),
        parameters: {'acao': actionId, 'usuario': _uidOutro},
      ),
      throwsA(isA<ServerException>()),
    );
  });
}

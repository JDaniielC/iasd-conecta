import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidNaoAdmin = '90000000-0000-0000-0000-000000000020';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidNaoAdmin, name: 'NaoAdmin ChurchAuth');
  });

  tearDownAll(() async {
    await cleanUpTestUser(conn, _uidNaoAdmin);
    await conn.close();
  });

  test('FR-006: quem não é Administrador não consegue adicionar Igreja', () async {
    await expectLater(
      asUser(conn, _uidNaoAdmin, () async {
        await conn.execute(
          Sql.named("insert into public.igrejas (nome) values ('Igreja Intrusa')"),
        );
      }),
      throwsA(isA<ServerException>()),
    );

    final rows = await conn.execute(
      Sql.named("select count(*) as total from public.igrejas where nome = 'Igreja Intrusa'"),
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });

  test('FR-006: quem não é Administrador não consegue arquivar Igreja', () async {
    final existente = await conn.execute('select id from public.igrejas limit 1');
    final churchId = existente.single.toColumnMap()['id'];

    await asUser(conn, _uidNaoAdmin, () async {
      await conn.execute(
        Sql.named('update public.igrejas set arquivada_em = now() where id = @id'),
        parameters: {'id': churchId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select arquivada_em from public.igrejas where id = @id'),
      parameters: {'id': churchId},
    );
    expect(rows.single.toColumnMap()['arquivada_em'], isNull);
  });
}

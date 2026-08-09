import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidNaoAdmin = '90000000-0000-0000-0000-000000000020';

void main() {
  late Connection conn;

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidNaoAdmin, name: 'NaoAdmin ChurchAuth');
  });

  tearDownAll(() async {
    await limparUsuarioDeTeste(conn, _uidNaoAdmin);
    await conn.close();
  });

  test('FR-006: quem não é Administrador não consegue adicionar Igreja', () async {
    await expectLater(
      comoUsuario(_uidNaoAdmin, () async {
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

    await comoUsuario(_uidNaoAdmin, () async {
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

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidNaoAdmin = '90000000-0000-0000-0000-000000000010';
const _uidAlvo = '90000000-0000-0000-0000-000000000011';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidNaoAdmin, name: 'NaoAdmin PromoteAuth');
    await createTestProfile(conn, _uidAlvo, name: 'Alvo PromoteAuth');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAlvo},
    );
    await cleanUpTestUser(conn, _uidNaoAdmin);
    await cleanUpTestUser(conn, _uidAlvo);
    await conn.close();
  });

  test('FR-003: quem não é Administrador não consegue promover ninguém', () async {
    await expectLater(
      asUser(conn, _uidNaoAdmin, () async {
        await conn.execute(
          Sql.named(
            'insert into public.administradores_distrito (usuario_id, promovido_por) '
            'values (@alvo, @naoAdmin)',
          ),
          parameters: {'alvo': _uidAlvo, 'naoAdmin': _uidNaoAdmin},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidNaoAdmin = '90000000-0000-0000-0000-000000000010';
const _uidAlvo = '90000000-0000-0000-0000-000000000011';

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
    await criarPerfilDeTeste(conn, _uidNaoAdmin, name: 'NaoAdmin PromoteAuth');
    await criarPerfilDeTeste(conn, _uidAlvo, name: 'Alvo PromoteAuth');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAlvo},
    );
    await limparUsuarioDeTeste(conn, _uidNaoAdmin);
    await limparUsuarioDeTeste(conn, _uidAlvo);
    await conn.close();
  });

  test('FR-003: quem não é Administrador não consegue promover ninguém', () async {
    await expectLater(
      comoUsuario(_uidNaoAdmin, () async {
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

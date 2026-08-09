import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000012';
const _uidSoPerfil = '90000000-0000-0000-0000-000000000013';
const _uidComConta = '90000000-0000-0000-0000-000000000014';

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
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin RequiresAccount');
    await criarPerfilSemContaDeTeste(conn, _uidSoPerfil, name: 'SoPerfil RequiresAccount');
    await criarPerfilDeTeste(conn, _uidComConta, name: 'ComConta RequiresAccount');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id in (@admin, @comConta)',
      ),
      parameters: {'admin': _uidAdmin, 'comConta': _uidComConta},
    );
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await limparUsuarioDeTeste(conn, _uidSoPerfil);
    await limparUsuarioDeTeste(conn, _uidComConta);
    await conn.close();
  });

  test('FR-002: promover Usuário só com Perfil (sem Conta) falha', () async {
    await expectLater(
      comoUsuario(_uidAdmin, () async {
        await conn.execute(
          Sql.named(
            'insert into public.administradores_distrito (usuario_id, promovido_por) '
            'values (@alvo, @admin)',
          ),
          parameters: {'alvo': _uidSoPerfil, 'admin': _uidAdmin},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-001: promover Usuário com Conta funciona', () async {
    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named(
          'insert into public.administradores_distrito (usuario_id, promovido_por) '
          'values (@alvo, @admin)',
        ),
        parameters: {'alvo': _uidComConta, 'admin': _uidAdmin},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.administradores_distrito where usuario_id = @id',
      ),
      parameters: {'id': _uidComConta},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}

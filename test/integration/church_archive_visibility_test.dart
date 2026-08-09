import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000021';

void main() {
  late Connection conn;
  late Object churchId;

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      // Limpa role E o GUC de jwt.claims — sem isso, um `set role anon`
      // depois ainda enxergaria o claim antigo (RESET ROLE não limpa GUC
      // customizado; achado durante a validação manual desta feature).
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin ArchiveVisibility');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);

    final rows = await conn.execute(
      Sql.named("insert into public.igrejas (nome) values ('Igreja Pra Arquivar') returning id"),
    );
    churchId = rows.single.toColumnMap()['id']!;

    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('update public.igrejas set arquivada_em = now() where id = @id'),
        parameters: {'id': churchId},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.igrejas where id = @id'),
      parameters: {'id': churchId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-007: Igreja arquivada não aparece pro papel anon (Visitante)', () async {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
    await conn.execute('set role anon');
    try {
      final rows = await conn.execute(
        Sql.named('select count(*) as total from public.igrejas where id = @id'),
        parameters: {'id': churchId},
      );
      expect(rows.single.toColumnMap()['total'], 0);
    } finally {
      await conn.execute('reset role');
    }
  });

  test('FR-008: Igreja arquivada continua visível pro Administrador', () async {
    await comoUsuario(_uidAdmin, () async {
      final rows = await conn.execute(
        Sql.named('select count(*) as total from public.igrejas where id = @id'),
        parameters: {'id': churchId},
      );
      expect(rows.single.toColumnMap()['total'], 1);
    });
  });
}

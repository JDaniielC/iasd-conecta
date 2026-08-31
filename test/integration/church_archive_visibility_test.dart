import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000021';

/// Visitante: pessoa sem cadastro, e por isso sem linha em `perfis`. TEM
/// sessão — `signInAnonymously` no arranque do app. Até 2026-08-16 este arquivo
/// o representava como `anon`, que é a requisição sem credencial nenhuma e não
/// é o que o app produz.
const _uidVisitor = '90000000-0000-0000-0000-0000000000f1';

void main() {
  late Connection conn;
  late Object churchId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAdmin, name: 'Admin ArchiveVisibility');
    await createTestDistrictAdmin(conn, _uidAdmin);
    await createTestVisitor(conn, _uidVisitor);

    final rows = await conn.execute(
      Sql.named(
        "insert into public.igrejas (nome) values ('Igreja Pra Arquivar') returning id",
      ),
    );
    churchId = rows.single.toColumnMap()['id']!;

    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named(
          'update public.igrejas set arquivada_em = now() where id = @id',
        ),
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
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @id',
      ),
      parameters: {'id': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidAdmin);
    await conn.close();
  });

  test('FR-007: Igreja arquivada não aparece pro Visitante', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named(
          'select count(*) as total from public.igrejas where id = @id',
        ),
        parameters: {'id': churchId},
      );
      expect(rows.single.toColumnMap()['total'], 0);
    });
  });

  test('FR-008: Igreja arquivada continua visível pro Administrador', () async {
    await asUser(conn, _uidAdmin, () async {
      final rows = await conn.execute(
        Sql.named(
          'select count(*) as total from public.igrejas where id = @id',
        ),
        parameters: {'id': churchId},
      );
      expect(rows.single.toColumnMap()['total'], 1);
    });
  });
}

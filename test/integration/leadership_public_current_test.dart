import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidLider = '90000000-0000-0000-0000-000000000050';

/// Visitante: pessoa sem cadastro, e por isso sem linha em `perfis`. TEM
/// sessão — `signInAnonymously` no arranque do app. Até 2026-08-16 este arquivo
/// o representava como `anon`, que é a requisição sem credencial nenhuma e não
/// é o que o app produz.
const _uidVisitor = '90000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidLider, name: 'Lider PublicCurrent');
    await createTestVisitor(conn, _uidVisitor);
    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipPublicCurrent', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidLider},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;
    // Confirmada do ano corrente
    await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        "values (@grupo, @uid, extract(year from now())::int, now(), @uid)",
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
    // Confirmada de um ano anterior (mesmo grupo, outro ano — não conta como atual)
    await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        "values (@grupo, @uid, extract(year from now())::int - 1, now(), @uid)",
      ),
      parameters: {'grupo': groupId, 'uid': _uidLider},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.liderancas where grupo_id = @id'),
      parameters: {'id': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': groupId},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidLider);
    await conn.close();
  });

  test(
    'FR-006/FR-008: só a confirmada do ano corrente conta como atual',
    () async {
      final rows = await conn.execute(
        Sql.named(
          'select ano from public.liderancas '
          'where grupo_id = @grupo and confirmado_em is not null and rejeitado_em is null '
          'and ano = extract(year from now())::int',
        ),
        parameters: {'grupo': groupId},
      );
      expect(rows, hasLength(1));
    },
  );

  test('FR-006: visível ao Visitante sem cadastro', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named(
          'select ano from public.liderancas where grupo_id = @grupo '
          'and confirmado_em is not null',
        ),
        parameters: {'grupo': groupId},
      );
      expect(rows, hasLength(2));
    });
  });
}

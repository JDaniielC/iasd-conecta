import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '40000000-0000-0000-0000-000000000003';

/// Visitante: sem cadastro, e por isso sem linha em `perfis`. TEM sessão.
///
/// Até 2026-08-16 estes testes rodavam como `anon`. FR-005 e FR-006 falam de
/// quem não tem cadastro; sob `anon` o que se media era o `grant` de tabela, e
/// a policy que os FRs descrevem ficava sem prova.
const _uidVisitor = '40000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono Publico');
    await createTestVisitor(conn, _uidVisitor);
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Público', 'Ministério Jovem', 'sábados 16h', 'Sede', @dono) "
        "returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidOwner},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  test('FR-005: Visitante sem cadastro vê grupos', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named('select nome from public.grupos where id = @id'),
        parameters: {'id': groupId},
      );
      expect(rows.single.toColumnMap()['nome'], 'Grupo Público');
    });
  });

  test('FR-006: Visitante vê a lista de participantes', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named(
          'select usuario_id from public.participacoes_grupo where grupo_id = @id',
        ),
        parameters: {'id': groupId},
      );
      expect(rows, isNotEmpty);
    });
  });

  test('Visitante não consegue inserir grupo', () async {
    // Sem cadastro não há `perfis`, e `dono_id` referencia lá. Sob `anon` isto
    // passava por falta de `grant insert` — barreira anterior à regra.
    await asVisitor(conn, _uidVisitor, () async {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.grupos (nome, categoria, horario, local, dono_id) "
            "values ('Invasor', 'Jovem', '19h', 'Sede', @dono)",
          ),
          parameters: {'dono': _uidOwner},
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });
}

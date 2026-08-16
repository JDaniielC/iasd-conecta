import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000022';
const _uidOutsider = '50000000-0000-0000-0000-000000000023';

/// Visitante: pessoa sem cadastro, e por isso sem linha em `perfis`. TEM
/// sessão — `signInAnonymously` no arranque do app.
///
/// Até 2026-08-16 estes testes rodavam como `anon` e se chamavam "papel anon
/// (Visitante)". Os dois não são a mesma coisa, e a diferença é o que este
/// arquivo existe para provar: FR-010 é sobre quem não tem cadastro, e sob
/// `anon` o que se media era o `grant` de tabela, não a policy.
const _uidVisitor = '50000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador Publico');
    await createTestProfile(conn, _uidOutsider, name: 'De Fora Publico');
    await createTestVisitor(conn, _uidVisitor);
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Ação Pública', now() + interval '5 days', 'Sede', @criador) returning id",
      ),
      parameters: {'criador': _uidCreator},
    );
    actionId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': actionId},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidOutsider);
    await cleanUpTestUser(conn, _uidCreator);
    await conn.close();
  });

  test('FR-010: Visitante sem cadastro vê a Ação', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named('select nome from public.acoes where id = @id'),
        parameters: {'id': actionId},
      );
      expect(rows.single.toColumnMap()['nome'], 'Ação Pública');
    });
  });

  test('FR-010: Visitante vê a lista de confirmados', () async {
    await asVisitor(conn, _uidVisitor, () async {
      final rows = await conn.execute(
        Sql.named(
          'select usuario_id from public.confirmacoes_acao where acao_id = @id',
        ),
        parameters: {'id': actionId},
      );
      expect(rows, isNotEmpty);
    });
  });

  test('FR-011: Visitante não consegue confirmar presença', () async {
    // Sem cadastro não há linha em `perfis`, e a FK de `confirmacoes_acao`
    // aponta para lá. Sob `anon` isto passava por falta de `grant` — barreira
    // anterior à regra que o FR-011 descreve.
    await asVisitor(conn, _uidVisitor, () async {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @criador)",
          ),
          parameters: {'acao': actionId, 'criador': _uidCreator},
        ),
        throwsA(isA<ServerException>()),
      );
    });
  });

  // ---------------------------------------------------------------------
  // Change acao-direcionada-a-grupo — o lado que impede a policy nova de
  // esconder o que não devia.
  //
  // `acoes_select_public using (true)` virou `acoes_select_visivel`, com um
  // `or exists (...)`. O risco aqui é o INVERSO do usual: uma condição escrita
  // errado não vaza — ela some com a Ação pública de todo mundo. Os dois casos
  // abaixo são o contrapeso dos testes de acao_restrita_*; um lado sozinho não
  // prova nada.
  // ---------------------------------------------------------------------

  test(
    'Ação pública sem Grupo continua visível para autenticado de fora',
    () async {
      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uidOutsider\",\"role\":\"authenticated\"}'",
      );
      try {
        final rows = await conn.execute(
          Sql.named('select nome from public.acoes where id = @id'),
          parameters: {'id': actionId},
        );
        expect(rows.single.toColumnMap()['nome'], 'Ação Pública');
      } finally {
        await conn.execute('reset role');
        await conn.execute('reset request.jwt.claims');
      }
    },
  );

  test(
    'confirmações de Ação pública continuam legíveis para autenticado de fora',
    () async {
      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uidOutsider\",\"role\":\"authenticated\"}'",
      );
      try {
        final rows = await conn.execute(
          Sql.named(
            'select usuario_id from public.confirmacoes_acao where acao_id = @id',
          ),
          parameters: {'id': actionId},
        );
        expect(rows, isNotEmpty);
      } finally {
        await conn.execute('reset role');
        await conn.execute('reset request.jwt.claims');
      }
    },
  );
}

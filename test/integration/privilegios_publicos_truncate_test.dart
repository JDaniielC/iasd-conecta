import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// `PENDENCIAS.md` § 2.2 / openspec `revogar-truncate-de-anon-e-authenticated`.
///
/// `TRUNCATE` ignora RLS por completo e não dispara gatilho `after delete` —
/// as duas garantias sobre as quais este projeto constrói privacidade e
/// limpeza de arquivo (feature 013). O default do fornecedor concedia
/// TRUNCATE/REFERENCES/TRIGGER a `anon`/`authenticated` em toda tabela de
/// `public`; a migration `20260811120000` revoga isso e fecha o default pra
/// tabela futura.
///
/// As três tabelas do primeiro teste têm natureza deliberadamente diferente
/// — a prova não é "TRUNCATE falha em uma tabela qualquer", é "falha em
/// qualquer tabela, independente do que ela é":
///  - `acoes`: tem policy de SELECT pública (`acoes_select_public`) — TRUNCATE
///    contorna RLS, então "todo mundo pode ler" não deveria significar "todo
///    mundo pode apagar tudo de uma vez".
///  - `perfis`: tem gatilho (`perfis_carimbar_consentimento_trigger`) — é
///    justamente o tipo de tabela onde "não dispara `after delete`" doeria.
///  - `participacoes_grupo`: tabela de junção (grupo × usuário) — não tem
///    RLS de leitura pública nem gatilho, é o caso "nenhuma das duas coisas
///    especiais, mesmo assim continua fechada".
void main() {
  late Connection conn;

  Future<void> asAuthenticated(Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    try {
      await action();
    } finally {
      await conn.execute('reset role');
    }
  }

  Future<void> expectTruncateDenied(String table) async {
    await asAuthenticated(() async {
      await expectLater(
        conn.execute('truncate table public.$table'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.code,
            'code',
            '42501', // insufficient_privilege
          ),
        ),
      );
    });
  }

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  test(
    'authenticated não consegue truncar acoes (RLS de leitura pública)',
    () => expectTruncateDenied('acoes'),
  );

  test(
    'authenticated não consegue truncar perfis (tabela com gatilho)',
    () => expectTruncateDenied('perfis'),
  );

  test(
    'authenticated não consegue truncar participacoes_grupo (tabela de junção)',
    () => expectTruncateDenied('participacoes_grupo'),
  );

  test(
    'tabela criada numa transação revertida nasce sem TRUNCATE/REFERENCES/'
    'TRIGGER pra anon/authenticated — prova do alter default privileges',
    () async {
      // Tudo dentro de uma transação: o INSERT em information_schema
      // enxerga o CREATE TABLE ainda não commitado da mesma sessão, e o
      // ROLLBACK no fim garante que a tabela de teste não sobrevive nem
      // precisa de limpeza manual.
      await conn.execute('begin');
      try {
        await conn.execute(
          'create table public.__teste_default_privileges_truncate (id int)',
        );

        final grants = await conn.execute(
          Sql.named(
            'select grantee, privilege_type '
            'from information_schema.role_table_grants '
            "where table_schema = 'public' "
            '  and table_name = @t '
            "  and grantee in ('anon', 'authenticated') "
            "  and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER')",
          ),
          parameters: {'t': '__teste_default_privileges_truncate'},
        );

        expect(
          grants,
          isEmpty,
          reason: 'tabela nova não deveria herdar TRUNCATE/REFERENCES/'
              'TRIGGER pra anon/authenticated depois do alter default '
              'privileges — encontrado: '
              '${grants.map((r) => r.toColumnMap()).toList()}',
        );
      } finally {
        await conn.execute('rollback');
      }
    },
  );
}

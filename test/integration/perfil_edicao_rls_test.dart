import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 016 — corrigir o próprio Perfil, e só o próprio.
///
/// `perfis_update_own` existe desde 2026-07-23 e nunca foi exercida por
/// nenhuma linha de código. Esta feature é a primeira consumidora dela, então
/// este arquivo é a primeira vez que alguém verifica se ela realmente segura o
/// que promete — e é o que responde FR-013 ("garantido no banco, não só na
/// tela") e SC-004 ("inclusive por chamada direta que não passe pela tela").
///
/// O caso (b) é o que explica por que esta feature não precisou de migration:
/// a policy tem `using` e **não** tem `with check`, e em Postgres o `using` de
/// um UPDATE vale também como checagem da linha nova. Sem isso, alguém poderia
/// reatribuir o próprio Perfil para outro id.

const _uidA = '93000000-0000-0000-0000-000000000001';
const _uidB = '93000000-0000-0000-0000-000000000002';
const _uidMinor = '93000000-0000-0000-0000-000000000003';

const _allUids = [_uidA, _uidB, _uidMinor];

void main() {
  late Connection conn;
  late String churchId;

  Future<Map<String, dynamic>> readProfile(String uid) async {
    final r = await conn.execute(
      Sql.named(
        'select nome, apelido, igreja_id, telefone, idade, genero, '
        'consentimento_lgpd_aceito_em, consentimento_lgpd_igreja_aceito_em '
        'from public.perfis where id = @u',
      ),
      parameters: {'u': uid},
    );
    return r.first.toColumnMap();
  }

  setUpAll(() async {
    conn = await openTestConnection();
    final c = await conn.execute('select id from public.igrejas limit 1');
    churchId = c.first[0] as String;
    await createTestProfile(conn, _uidA, name: 'Pessoa A Edicao');
    await createTestProfile(conn, _uidB, name: 'Pessoa B Edicao');
    await createTestProfile(conn, _uidMinor, name: 'Pessoa Menor Edicao');
    // Menor de idade precisa de Apelido — a constraint vale no insert também.
    await conn.execute(
      Sql.named(
        "update public.perfis set idade = 15, apelido = 'Nino' where id = @u",
      ),
      parameters: {'u': _uidMinor},
    );
  });

  tearDownAll(() async {
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    '(a) FR-013/SC-004: A não altera o Perfil de B — afeta 0 linhas',
    () async {
      final before = await readProfile(_uidB);

      await asUser(conn, _uidA, () async {
        final r = await conn.execute(
          Sql.named(
            "update public.perfis set nome = 'Invadido' where id = @u",
          ),
          parameters: {'u': _uidB},
        );
        // A RLS não levanta erro: ela simplesmente não deixa a linha ser
        // vista pelo UPDATE. Zero linhas afetadas, em silêncio.
        expect(r.affectedRows, 0);
      });

      expect(await readProfile(_uidB), before);
    },
  );

  test(
    '(b) FR-013: A não consegue reatribuir o próprio Perfil para o id de B',
    () async {
      await expectLater(
        asUser(conn, _uidA, () async {
          await conn.execute(
            Sql.named('update public.perfis set id = @b where id = @a'),
            parameters: {'a': _uidA, 'b': _uidB},
          );
        }),
        throwsA(isA<Exception>()),
        reason: 'o `using` da policy vale como checagem da linha nova; é por '
            'isso que esta feature não precisou de migration',
      );

      final a = await readProfile(_uidA);
      expect(a['nome'], isNotNull);
    },
  );

  test(
    '(c) FR-008/FR-012: nome recusado pela moderação não altera nada',
    () async {
      final before = await readProfile(_uidA);

      await expectLater(
        asUser(conn, _uidA, () async {
          await conn.execute(
            Sql.named("update public.perfis set nome = 'idiota' where id = @u"),
            parameters: {'u': _uidA},
          );
        }),
        throwsA(isA<Exception>()),
      );

      // A metade banco de FR-012: depois da recusa, a linha está exatamente
      // como estava. Não existe meio-salvamento.
      expect(await readProfile(_uidA), before);
    },
  );

  test(
    '(d) FR-009/FR-012: menor de idade não consegue esvaziar o Apelido',
    () async {
      final before = await readProfile(_uidMinor);

      await expectLater(
        asUser(conn, _uidMinor, () async {
          await conn.execute(
            Sql.named('update public.perfis set apelido = null where id = @u'),
            parameters: {'u': _uidMinor},
          );
        }),
        throwsA(isA<Exception>()),
      );

      expect(await readProfile(_uidMinor), before);
    },
  );

  test(
    '(e) FR-011/FR-012: Igreja sem o consentimento destacado é recusada',
    () async {
      final before = await readProfile(_uidA);

      await expectLater(
        asUser(conn, _uidA, () async {
          await conn.execute(
            Sql.named(
              'update public.perfis set igreja_id = @i, '
              'consentimento_lgpd_igreja_aceito_em = null where id = @u',
            ),
            parameters: {'u': _uidA, 'i': churchId},
          );
        }),
        throwsA(isA<Exception>()),
      );

      expect(await readProfile(_uidA), before);
    },
  );

  test(
    '(f) FR-007/FR-012: o caminho legítimo muda as cinco colunas juntas, e '
    'só elas',
    () async {
      final before = await readProfile(_uidA);

      await asUser(conn, _uidA, () async {
        await conn.execute(
          Sql.named(
            'update public.perfis set '
            "nome = 'Ana Corrigida', apelido = 'Aninha', igreja_id = @i, "
            "telefone = '81999990000', "
            'consentimento_lgpd_igreja_aceito_em = now() '
            'where id = @u',
          ),
          parameters: {'u': _uidA, 'i': churchId},
        );
      });

      final after = await readProfile(_uidA);
      expect(after['nome'], 'Ana Corrigida');
      expect(after['apelido'], 'Aninha');
      expect(after['igreja_id'], churchId);
      expect(after['telefone'], '81999990000');
      expect(after['consentimento_lgpd_igreja_aceito_em'], isNotNull);

      // E o que não é editável não se moveu. A data do consentimento LGPD é a
      // prova da base legal: se ela virasse "última vez que mexi no cadastro",
      // o registro que a feature 017 acabou de criar seria perdido.
      expect(after['idade'], before['idade']);
      expect(after['genero'], before['genero']);
      expect(
        after['consentimento_lgpd_aceito_em'],
        before['consentimento_lgpd_aceito_em'],
      );
    },
  );

  // (g)/(h) — change `endurecer-grant-update-perfis`, achado 5 de
  // SECURITY-AUDIT.md / PENDENCIAS.md § 2.1. `perfis_update_own` (acima)
  // protege a LINHA; estes dois casos provam que o `grant update` por coluna
  // (`20260811160000_grant_update_perfis_por_coluna.sql`) protege a COLUNA —
  // a garantia que a policy nunca deu. Erro `42501` é o SQLSTATE de
  // `permission denied`, levantado pelo próprio Postgres antes de a policy
  // rodar, não uma exceção genérica de aplicação.
  test(
    '(g) escrever a própria idade é recusado com permission denied (42501)',
    () async {
      final before = await readProfile(_uidA);

      await expectLater(
        asUser(conn, _uidA, () async {
          await conn.execute(
            Sql.named('update public.perfis set idade = 99 where id = @u'),
            parameters: {'u': _uidA},
          );
        }),
        throwsA(isA<ServerException>().having((e) => e.code, 'código', '42501')),
      );

      expect(await readProfile(_uidA), before);
    },
  );

  test(
    '(h) escrever o próprio genero é recusado com permission denied (42501)',
    () async {
      final before = await readProfile(_uidA);

      await expectLater(
        asUser(conn, _uidA, () async {
          await conn.execute(
            Sql.named(
              "update public.perfis set genero = 'masculino' where id = @u",
            ),
            parameters: {'u': _uidA},
          );
        }),
        throwsA(isA<ServerException>().having((e) => e.code, 'código', '42501')),
      );

      expect(await readProfile(_uidA), before);
    },
  );
}

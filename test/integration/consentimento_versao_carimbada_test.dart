import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 017 — o banco carimba, o cliente não.
///
/// A regra que resume a feature: **o cliente diz SE a pessoa aceitou; o banco
/// diz QUANDO e SOB QUAL TEXTO.** O caso (b) é o teste central — ele manda uma
/// versão explícita no `insert` e prova que ela é descartada. Sem ele, a
/// coluna existiria mas valeria o que o cliente dissesse, e um registro de base
/// legal que vale o que o cliente disser não demonstra nada.

const _uidPlain = '96000000-0000-0000-0000-000000000001';
const _uidForged = '96000000-0000-0000-0000-000000000002';
const _uidBackdated = '96000000-0000-0000-0000-000000000003';
const _uidChurch = '96000000-0000-0000-0000-000000000004';
const _uidLater = '96000000-0000-0000-0000-000000000005';
const _uidSeeded = '96000000-0000-0000-0000-000000000006';
const _uidNoConsent = '96000000-0000-0000-0000-000000000007';

const _allUids = [
  _uidPlain,
  _uidForged,
  _uidBackdated,
  _uidChurch,
  _uidLater,
  _uidSeeded,
  _uidNoConsent,
];

void main() {
  late Connection conn;
  late String currentVersion;
  late String churchId;

  Future<String?> stampedVersionOf(String uid, {bool church = false}) async {
    final column =
        church ? 'consentimento_lgpd_igreja_versao' : 'consentimento_lgpd_versao';
    final r = await conn.execute(
      Sql.named('select $column from public.perfis where id = @u'),
      parameters: {'u': uid},
    );
    return r.first[0] as String?;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    final v = await conn.execute('select public.versao_texto_legal_vigente()');
    currentVersion = v.first[0] as String;
    final c = await conn.execute('select id from public.igrejas limit 1');
    churchId = c.first[0] as String;
    for (final uid in _allUids) {
      await createTestUser(conn, uid);
    }
  });

  tearDownAll(() async {
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('(a) FR-001/SC-001: cadastrar grava a versão vigente ao lado da data',
      () async {
    await asUser(conn, _uidPlain, () async {
      await conn.execute(
        Sql.named(
          'insert into public.perfis '
          '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
          "values (@u, 'Pessoa Simples', 'feminino', 30, now())",
        ),
        parameters: {'u': _uidPlain},
      );
    });

    expect(await stampedVersionOf(_uidPlain), currentVersion);
    final r = await conn.execute(
      Sql.named(
        'select consentimento_lgpd_aceito_em is not null, '
        'abs(extract(epoch from (now() - consentimento_lgpd_aceito_em))) < 60 '
        'from public.perfis where id = @u',
      ),
      parameters: {'u': _uidPlain},
    );
    expect(r.first[0], isTrue);
    expect(r.first[1], isTrue, reason: 'a data é o now() do banco');
  });

  test(
    '(b) FR-004: versão mandada pelo cliente é DESCARTADA — o teste central',
    () async {
      await asUser(conn, _uidForged, () async {
        await conn.execute(
          Sql.named(
            'insert into public.perfis '
            '(id, nome, genero, idade, consentimento_lgpd_aceito_em, '
            'consentimento_lgpd_versao) '
            "values (@u, 'Pessoa Forjada', 'feminino', 30, now(), '1.1')",
          ),
          parameters: {'u': _uidForged},
        );
      });

      expect(
        await stampedVersionOf(_uidForged),
        currentVersion,
        reason: 'o cliente mandou 1.1; vale o que o banco carimbou. Um '
            'registro de base legal que vale o que o cliente disser não '
            'demonstra nada',
      );
    },
  );

  test('(c) FR-004: data antiga mandada pelo cliente vira o now() do banco',
      () async {
    await asUser(conn, _uidBackdated, () async {
      await conn.execute(
        Sql.named(
          'insert into public.perfis '
          '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
          "values (@u, 'Pessoa Retroativa', 'feminino', 30, "
          "now() - interval '3 days')",
        ),
        parameters: {'u': _uidBackdated},
      );
    });

    // Data e versão precisam sair do MESMO relógio, senão elas descrevem
    // momentos diferentes e o par para de significar alguma coisa.
    final r = await conn.execute(
      Sql.named(
        'select abs(extract(epoch from (now() - consentimento_lgpd_aceito_em))) < 60 '
        'from public.perfis where id = @u',
      ),
      parameters: {'u': _uidBackdated},
    );
    expect(r.first[0], isTrue);
    expect(await stampedVersionOf(_uidBackdated), currentVersion);
  });

  test('(d) FR-003: consentimento de Igreja também carimba versão', () async {
    await asUser(conn, _uidChurch, () async {
      await conn.execute(
        Sql.named(
          'insert into public.perfis '
          '(id, nome, genero, idade, consentimento_lgpd_aceito_em, '
          'igreja_id, consentimento_lgpd_igreja_aceito_em) '
          "values (@u, 'Pessoa Com Igreja', 'feminino', 30, now(), @i, now())",
        ),
        parameters: {'u': _uidChurch, 'i': churchId},
      );
    });

    expect(await stampedVersionOf(_uidChurch), currentVersion);
    expect(await stampedVersionOf(_uidChurch, church: true), currentVersion);
  });

  test(
    '(e) FR-003: dar o consentimento de Igreja depois carimba a versão daquele '
    'instante; retirá-lo zera a versão junto',
    () async {
      await asUser(conn, _uidLater, () async {
        await conn.execute(
          Sql.named(
            'insert into public.perfis '
            '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
            "values (@u, 'Pessoa Depois', 'feminino', 30, now())",
          ),
          parameters: {'u': _uidLater},
        );
      });
      expect(await stampedVersionOf(_uidLater, church: true), isNull,
          reason: 'sem Igreja escolhida, não há aceite a versionar');

      // O caminho que a feature 016 (Meu Perfil) vai usar.
      await asUser(conn, _uidLater, () async {
        await conn.execute(
          Sql.named(
            'update public.perfis set igreja_id = @i, '
            'consentimento_lgpd_igreja_aceito_em = now() where id = @u',
          ),
          parameters: {'u': _uidLater, 'i': churchId},
        );
      });
      expect(await stampedVersionOf(_uidLater, church: true), currentVersion);

      // Retirar a Igreja: versão sem aceite correspondente seria lixo.
      await asUser(conn, _uidLater, () async {
        await conn.execute(
          Sql.named(
            'update public.perfis set igreja_id = null, '
            'consentimento_lgpd_igreja_aceito_em = null where id = @u',
          ),
          parameters: {'u': _uidLater},
        );
      });
      expect(await stampedVersionOf(_uidLater, church: true), isNull);
    },
  );

  test(
    '(f) SC-005: publicar versão nova muda o carimbo sem uma linha de código '
    'mudar',
    () async {
      const seededVersion = '1.2-teste';

      // Tudo numa transação que termina em rollback. `versoes_texto_legal` é
      // catálogo global: uma linha nova com vigente_desde = now() vira a versão
      // vigente para TODO MUNDO, e
      // versao_texto_legal_registro_test.dart — que roda em paralelo — passaria
      // a ver o banco divergindo do Dart e falharia por culpa deste teste.
      // Dado não commitado é invisível às outras sessões, e visível a esta.
      await conn.execute('begin');
      try {
        await conn.execute(
          Sql.named(
            'insert into public.versoes_texto_legal (versao, vigente_desde) '
            'values (@v, now())',
          ),
          parameters: {'v': seededVersion},
        );

        // Sem `asUser`: `set role` dentro da transação seria revertido junto, e
        // o ponto aqui é o carimbo, não a identidade de quem insere.
        await conn.execute(
          Sql.named(
            'insert into public.perfis '
            '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
            "values (@u, 'Pessoa Nova Versao', 'feminino', 30, now())",
          ),
          parameters: {'u': _uidSeeded},
        );

        expect(await stampedVersionOf(_uidSeeded), seededVersion,
            reason: 'publicar versão nova muda o que é carimbado sem uma linha '
                'de código Dart mudar');
      } finally {
        await conn.execute('rollback');
      }
    },
  );

  test(
    '(g) FR-001: o gatilho NÃO fabrica consentimento para quem não deu',
    () async {
      // A primeira versão deste gatilho carimbava now() em todo INSERT, sem
      // olhar o que veio. Quem omitisse a coluna ganhava a data de graça, e o
      // `not null` que torna o consentimento obrigatório desde a feature 001
      // deixava de disparar — uma feature de conformidade registrando aceite de
      // quem nunca aceitou.
      //
      // O sinal é o campo vir preenchido. Campo ausente é ausência de sinal.
      await expectLater(
        asUser(conn, _uidNoConsent, () async {
          await conn.execute(
            Sql.named(
              'insert into public.perfis (id, nome, genero, idade) '
              "values (@u, 'Pessoa Sem Consentimento', 'feminino', 30)",
            ),
            parameters: {'u': _uidNoConsent},
          );
        }),
        throwsA(isA<Exception>()),
      );
    },
  );
}

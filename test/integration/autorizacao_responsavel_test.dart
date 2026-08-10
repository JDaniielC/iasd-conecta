import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 015 — a autorização do Responsável vale NO BANCO.
///
/// A tela pode pedir o que quiser; se a regra não estiver aqui, um `insert`
/// direto cadastra criança sem autorização nenhuma e a Política passa a
/// descrever algo que o app não faz. Era esse o problema que originou a
/// feature.
///
/// Nenhuma idade literal neste arquivo: as idades vêm de
/// `select public.limiar_crianca()`. Repetir o número aqui criaria um segundo
/// lugar onde a decisão de produto mora.

const _childUid = '89000000-0000-0000-0000-000000000001';
const _adultUid = '89000000-0000-0000-0000-000000000002';
const _legacyChildUid = '89000000-0000-0000-0000-000000000003';
const _thresholdAgeUid = '89000000-0000-0000-0000-000000000004';

const _allUids = [_childUid, _adultUid, _legacyChildUid, _thresholdAgeUid];

void main() {
  late Connection conn;
  late int childAgeThresholdFromDb;

  Future<void> asUser(String uid, Future<void> Function() action) async {
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

  Future<void> insertProfile({
    required String uid,
    required int age,
    String? guardianName,
    String? guardianContact,
    bool withTimestamp = true,
    bool withVersion = true,
  }) async {
    await conn.execute(
      Sql.named(
        'insert into public.perfis '
        '(id, nome, apelido, genero, idade, consentimento_lgpd_aceito_em, '
        'responsavel_nome, responsavel_contato, autorizacao_responsavel_em, '
        'autorizacao_responsavel_versao) '
        "values (@u, 'Pessoa Teste', 'Apelidinho', 'feminino', @age, now(), "
        '@gn, @gc, @ts, @v)',
      ),
      parameters: {
        'u': uid,
        'age': age,
        'gn': guardianName,
        'gc': guardianContact,
        'ts': (guardianName != null && withTimestamp)
            ? DateTime.now().toUtc()
            : null,
        'v': (guardianName != null && withVersion) ? '1.2' : null,
      },
    );
  }

  Future<Map<String, dynamic>> readGuardianColumns(String uid) async {
    final r = await conn.execute(
      Sql.named(
        'select responsavel_nome, responsavel_contato, '
        'autorizacao_responsavel_em, autorizacao_responsavel_versao '
        'from public.perfis where id = @u',
      ),
      parameters: {'u': uid},
    );
    return r.first.toColumnMap();
  }

  setUpAll(() async {
    conn = await openTestConnection();
    final r = await conn.execute('select public.limiar_crianca()');
    childAgeThresholdFromDb = (r.first[0] as num).toInt();
    for (final uid in _allUids) {
      await createTestUser(conn, uid);
    }
  });

  tearDown(() async {
    // A linha antiga é somente-leitura, então limpar exige o bypass — o mesmo
    // que excluir_minha_conta usa.
    await conn.execute(
      "select set_config('app.bypass_autorizacao_responsavel', 'true', true)",
    );
    for (final uid in _allUids) {
      await conn.execute(
        Sql.named('delete from public.perfis where id = @u'),
        parameters: {'u': uid},
      );
    }
    await conn.execute(
      "select set_config('app.bypass_autorizacao_responsavel', 'false', true)",
    );
  });

  tearDownAll(() async {
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    'FR-019: o limiar do banco e o do Dart são o mesmo número',
    () {
      // Uma asserção de uma linha no lugar de uma regra de disciplina. Sem ela,
      // as duas fontes divergem no dia em que alguém mudar só uma.
      expect(childAgeThresholdFromDb, childAgeThreshold);
    },
  );

  test(
    'FR-004/FR-009/SC-001: criança sem autorização é RECUSADA, mesmo por '
    'insert direto',
    () async {
      await expectLater(
        insertProfile(uid: _childUid, age: childAgeThresholdFromDb - 1),
        throwsA(isA<Exception>()),
        reason: 'este é o caminho que a tela não cobre e a feature existe '
            'para fechar',
      );
    },
  );

  test('FR-001: faltando só o contato, também é recusado', () async {
    await expectLater(
      insertProfile(
        uid: _childUid,
        age: childAgeThresholdFromDb - 1,
        guardianName: 'Maria Silva',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('FR-001: faltando só a data da autorização, também é recusado', () async {
    await expectLater(
      insertProfile(
        uid: _childUid,
        age: childAgeThresholdFromDb - 1,
        guardianName: 'Maria Silva',
        guardianContact: 'maria@exemplo.com',
        withTimestamp: false,
      ),
      throwsA(isA<Exception>()),
      reason: 'sem quando, a autorização não demonstra nada — o ônus da prova '
          'do consentimento é do controlador',
    );
  });

  test(
    'FR-007/SC-002: cadastro completo é aceito e guarda quem, contato, quando '
    'e sob qual versão',
    () async {
      await insertProfile(
        uid: _childUid,
        age: childAgeThresholdFromDb - 1,
        guardianName: 'Maria Silva',
        guardianContact: 'maria@exemplo.com',
      );

      final row = await readGuardianColumns(_childUid);
      expect(row['responsavel_nome'], 'Maria Silva');
      expect(row['responsavel_contato'], 'maria@exemplo.com');
      expect(row['autorizacao_responsavel_em'], isNotNull);
      expect(row['autorizacao_responsavel_versao'], isNotNull);
    },
  );

  test('FR-008: adulto com campos de responsável é RECUSADO', () async {
    // O caso real: o formulário mostrou os campos, a idade subiu, e o estado
    // ficou lá. Sem esta constraint, o app guardaria nome e telefone de um
    // terceiro sem nenhuma finalidade.
    await expectLater(
      insertProfile(
        uid: _adultUid,
        age: childAgeThresholdFromDb + 5,
        guardianName: 'Alguém',
        guardianContact: 'alguem@exemplo.com',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'idade EXATAMENTE no limiar não exige autorização — é o lado em que o '
    'limiar cai',
    () async {
      // Este teste é quem documenta a resposta do Edge Case. `idade < limiar`,
      // então quem tem a idade do limiar já é adolescente.
      await insertProfile(uid: _thresholdAgeUid, age: childAgeThresholdFromDb);

      final row = await readGuardianColumns(_thresholdAgeUid);
      expect(row['responsavel_nome'], isNull);
    },
  );

  group('o registro não se altera depois de gravado', () {
    setUp(() async {
      await insertProfile(
        uid: _childUid,
        age: childAgeThresholdFromDb - 1,
        guardianName: 'Maria Mae',
        guardianContact: 'maria@exemplo.com',
      );
    });

    test('FR-009: a própria criança não reescreve o nome do responsável',
        () async {
      // Antes desta feature isto passava: `'Maria Mae'` virava
      // `'Fulano Inventado'` com UPDATE 1, porque perfis_update_own é
      // `using (auth.uid() = id)` sem `with check` — ela confere QUEM mexe na
      // linha, nunca O QUÊ muda. WITH CHECK não resolveria: política RLS não
      // enxerga OLD. Gatilho é o único lugar onde OLD existe.
      await expectLater(
        asUser(_childUid, () async {
          await conn.execute(
            Sql.named("update public.perfis "
                "set responsavel_nome = 'Fulano Inventado' where id = @u"),
            parameters: {'u': _childUid},
          );
        }),
        throwsA(isA<Exception>()),
      );

      final row = await readGuardianColumns(_childUid);
      expect(row['responsavel_nome'], 'Maria Mae');
    });

    test('FR-009: nem a data da autorização', () async {
      await expectLater(
        asUser(_childUid, () async {
          await conn.execute(
            Sql.named('update public.perfis '
                'set autorizacao_responsavel_em = now() where id = @u'),
            parameters: {'u': _childUid},
          );
        }),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('cadastro antigo, anterior à feature', () {
    setUp(() async {
      // Semeado com o gatilho desligado e as constraints contornadas pelo
      // bypass — é o equivalente de uma linha que já estava no banco quando a
      // migration entrou.
      await conn.execute('begin');
      await conn.execute('alter table public.perfis '
          'drop constraint autorizacao_responsavel_crianca');
      await insertProfile(
        uid: _legacyChildUid,
        age: childAgeThresholdFromDb - 1,
      );
      await conn.execute('alter table public.perfis '
          'add constraint autorizacao_responsavel_crianca check ('
          'idade is null or idade >= public.limiar_crianca() or ('
          'responsavel_nome is not null and responsavel_contato is not null '
          'and autorizacao_responsavel_em is not null '
          'and autorizacao_responsavel_versao is not null)) not valid');
      await conn.execute('commit');
    });

    test('sobrevive à migration — a feature não corrige nem apaga', () async {
      final r = await conn.execute(
        Sql.named('select count(*) from public.perfis where id = @u'),
        parameters: {'u': _legacyChildUid},
      );
      expect((r.first[0] as num).toInt(), 1);
    });

    test(
      'mas vira SOMENTE-LEITURA: até mudar o telefone é recusado',
      () async {
        // `not valid` quer dizer "não confira as linhas que já estão aqui" —
        // NÃO quer dizer "só vale para linhas novas". Todo update passa a ser
        // verificado, inclusive de coluna sem relação nenhuma.
        await expectLater(
          asUser(_legacyChildUid, () async {
            await conn.execute(
              Sql.named("update public.perfis set telefone = '81999990000' "
                  'where id = @u'),
              parameters: {'u': _legacyChildUid},
            );
          }),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'LGPD art. 18 VI: mas a exclusão de conta continua funcionando',
      () async {
        // É o que salva a feature de virar um bug de conformidade pior do que
        // o que ela conserta: o update de anonimização zera `idade`, e as duas
        // constraints resultam em NULL e passam.
        await asUser(_legacyChildUid, () async {
          await conn.execute('select public.excluir_minha_conta()');
        });

        final r = await conn.execute(
          Sql.named('select nome, anonimizado_em is not null '
              'from public.perfis where id = @u'),
          parameters: {'u': _legacyChildUid},
        );
        expect(r.first[0], 'Membro removido');
        expect(r.first[1], isTrue);
      },
    );
  });

  test(
    'Princípio II: excluir a conta apaga o dado do Responsável, que é de '
    'terceiro',
    () async {
      await insertProfile(
        uid: _childUid,
        age: childAgeThresholdFromDb - 1,
        guardianName: 'Maria Silva',
        guardianContact: 'maria@exemplo.com',
      );

      await asUser(_childUid, () async {
        await conn.execute('select public.excluir_minha_conta()');
      });

      // Sem isto, o app excluiria a conta da criança e guardaria o nome e o
      // telefone da mãe — pessoa que não tem conta, não tem tela e não tem
      // como pedir exclusão.
      final row = await readGuardianColumns(_childUid);
      expect(row['responsavel_nome'], isNull);
      expect(row['responsavel_contato'], isNull);
      expect(row['autorizacao_responsavel_em'], isNull);
      expect(row['autorizacao_responsavel_versao'], isNull);
    },
  );
}

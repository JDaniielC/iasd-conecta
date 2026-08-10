import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 017, US2 — a coluna vira resposta.
///
/// `consentimentos_por_versao()` é `security definer` porque `perfis_select_own`
/// restringe a leitura à própria linha: sem escalar, a pergunta "quantas pessoas
/// estão sob cada versão" é irrespondível de dentro do app. Escalar privilégio
/// pede as duas provas que este arquivo dá: que só o Administrador do distrito
/// chama, e que a resposta é contagem e nunca identidade.

const _adminUid = '95000000-0000-0000-0000-000000000001';
const _plainUserUid = '95000000-0000-0000-0000-000000000002';
const _legacyUid = '95000000-0000-0000-0000-000000000003';
const _anonymizedUid = '95000000-0000-0000-0000-000000000004';

const _allUids = [_adminUid, _plainUserUid, _legacyUid, _anonymizedUid];

void main() {
  late Connection conn;
  late String currentVersion;

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

  /// Perfil anterior à feature 017: versão nula, impossível pelo caminho normal.
  Future<void> seedLegacyProfile(String uid) async {
    // Tudo numa transação: `alter table ... disable trigger` toma
    // ACCESS EXCLUSIVE e é GLOBAL. Fora de transação, o gatilho fica desligado
    // para todo mundo durante a janela, e `dart test` roda os arquivos em
    // paralelo — outro teste inserindo Perfil nesse instante gravaria sem
    // carimbo. Dentro da transação o lock é segurado até o commit, e ninguém
    // mais insere no meio.
    await conn.execute('begin');
    await conn.execute(
      'alter table public.perfis '
      'disable trigger perfis_carimbar_consentimento_trigger',
    );
    await conn.execute(
      Sql.named(
        'insert into public.perfis '
        '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
        "values (@u, 'Pessoa Antiga', 'feminino', 30, now())",
      ),
      parameters: {'u': uid},
    );
    await conn.execute(
      'alter table public.perfis '
      'enable trigger perfis_carimbar_consentimento_trigger',
    );
    await conn.execute('commit');
  }

  setUpAll(() async {
    conn = await openTestConnection();
    final v = await conn.execute('select public.versao_texto_legal_vigente()');
    currentVersion = v.first[0] as String;

    for (final uid in [_adminUid, _plainUserUid, _anonymizedUid]) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }
    await createTestUser(conn, _legacyUid);
    await seedLegacyProfile(_legacyUid);
    await createTestDistrictAdmin(conn, _adminUid);

    await conn.execute(
      Sql.named('update public.perfis set anonimizado_em = now() where id = @u'),
      parameters: {'u': _anonymizedUid},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _adminUid},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('(a) quem não é Administrador do distrito é recusado', () async {
    await expectLater(
      asUser(_plainUserUid, () async {
        await conn.execute('select * from public.consentimentos_por_versao()');
      }),
      throwsA(isA<Exception>()),
    );
  });

  test(
    '(b) FR-005/FR-006/SC-003: uma linha por versão, com a desconhecida '
    'contada à parte',
    () async {
      late List<List<dynamic>> rows;
      await asUser(_adminUid, () async {
        final r =
            await conn.execute('select * from public.consentimentos_por_versao()');
        rows = r.map((row) => row.toList()).toList();
      });

      final lgpdRows = rows.where((r) => r[0] == 'lgpd').toList();
      final knownRow =
          lgpdRows.firstWhere((r) => r[1] == currentVersion, orElse: () => []);
      final unknownRow =
          lgpdRows.firstWhere((r) => r[1] == null, orElse: () => []);

      expect(knownRow, isNotEmpty,
          reason: 'os cadastros novos aparecem sob a versão vigente');
      expect(unknownRow, isNotEmpty,
          reason: 'e o Perfil pré-feature aparece separado, como desconhecido');
      // A pergunta da US2 só é respondível se as duas contagens forem
      // distinguíveis. Somá-las seria a mesma mentira que preencher a coluna.
      expect(unknownRow[2], greaterThanOrEqualTo(1));
    },
  );

  test('(c) Princípio II: a resposta não traz coluna de identidade', () async {
    late List<String> columns;
    await asUser(_adminUid, () async {
      final r =
          await conn.execute('select * from public.consentimentos_por_versao()');
      columns = r.schema.columns.map((c) => c.columnName ?? '').toList();
    });

    expect(columns, ['tipo', 'versao', 'quantidade']);
    for (final forbidden in ['id', 'nome', 'apelido', 'usuario_id']) {
      expect(columns, isNot(contains(forbidden)));
    }
  });

  test('(d) Perfil anonimizado sai da contagem', () async {
    // Tudo numa transação com rollback, sob uma versão inventada só para este
    // caso. Duas razões, e as duas doeram antes:
    //
    // 1. Comparar o total da função contra `count(*) from public.perfis` não
    //    funciona: a função é security definer e enxerga todas as linhas, e o
    //    count direto roda como `authenticated`, onde `perfis_select_own` o
    //    limita à própria linha. Os dois números medem coisas diferentes.
    // 2. Qualquer asserção sobre total global é corrida — os arquivos de teste
    //    rodam em paralelo criando Perfil o tempo todo.
    //
    // Com uma versão exclusiva deste caso, a contagem daquele balde só depende
    // do que este teste inseriu.
    const isolatedVersion = '9.9-anon';
    const keptUid = '95000000-0000-0000-0000-00000000000a';
    const droppedUid = '95000000-0000-0000-0000-00000000000b';

    await conn.execute('begin');
    try {
      await conn.execute(
        Sql.named(
          'insert into public.versoes_texto_legal (versao, vigente_desde) '
          'values (@v, now())',
        ),
        parameters: {'v': isolatedVersion},
      );
      for (final uid in [keptUid, droppedUid]) {
        await conn.execute(
          Sql.named(
            'insert into auth.users (id, aud, role, instance_id) values '
            "(@u, 'authenticated', 'authenticated', "
            "'00000000-0000-0000-0000-000000000000')",
          ),
          parameters: {'u': uid},
        );
        await conn.execute(
          Sql.named(
            'insert into public.perfis '
            '(id, nome, genero, idade, consentimento_lgpd_aceito_em) '
            "values (@u, 'Pessoa Contagem', 'feminino', 30, now())",
          ),
          parameters: {'u': uid},
        );
      }
      await conn.execute(
        Sql.named(
          'update public.perfis set anonimizado_em = now() where id = @u',
        ),
        parameters: {'u': droppedUid},
      );

      await conn.execute('set local role authenticated');
      await conn.execute(
        "set local request.jwt.claims to "
        "'{\"sub\":\"$_adminUid\",\"role\":\"authenticated\"}'",
      );
      final r = await conn.execute(
        Sql.named(
          'select quantidade from public.consentimentos_por_versao() '
          "where tipo = 'lgpd' and versao = @v",
        ),
        parameters: {'v': isolatedVersion},
      );

      expect(r.length, 1, reason: 'um balde para essa versão');
      expect((r.first[0] as num).toInt(), 1,
          reason: 'dois Perfis foram criados sob essa versão e um foi '
              'anonimizado; quem foi anonimizado não é mais pessoa rastreada, '
              'e contá-lo inflaria a resposta');
    } finally {
      await conn.execute('rollback');
    }
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 017, US3 — honestidade sobre o passado.
///
/// Cadastro anterior a esta feature fica com versão **nula**, que quer dizer
/// *desconhecida* e mais nada. Preencher retroativamente com '1.0' ou '1.1'
/// seria um chute apresentado como fato — exatamente o que FR-007 proíbe.
///
/// O caso (d) é o mais importante do arquivo, e provavelmente da feature: ele
/// prova que quem se cadastrou antes **continua conseguindo apagar a conta**.
/// A tentação era declarar a coluna obrigatória com um `check ... not valid`,
/// que parece deixar as linhas antigas em paz. Não deixa: `not valid` é
/// verificado em todo UPDATE da linha, e `excluir_minha_conta` termina num
/// `update public.perfis set ...`. O Perfil antigo perderia o direito de
/// exclusão (LGPD art. 18, VI) — uma feature de conformidade criando um bug de
/// conformidade pior do que o que ela conserta.

const _legacyUid = '94000000-0000-0000-0000-000000000001';
const _legacyForDeleteUid = '94000000-0000-0000-0000-000000000002';

const _allUids = [_legacyUid, _legacyForDeleteUid];

void main() {
  late Connection conn;

  /// Perfil "pré-feature": versão nula.
  ///
  /// Precisa desligar o gatilho como superusuário, porque pelo caminho normal
  /// isso é impossível — e essa impossibilidade é justamente a garantia da US1.
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
        "values (@u, 'Pessoa Antiga', 'feminino', 30, now() - interval '30 days')",
      ),
      parameters: {'u': uid},
    );
    await conn.execute(
      'alter table public.perfis '
      'enable trigger perfis_carimbar_consentimento_trigger',
    );
    await conn.execute('commit');
  }

  Future<String?> versionOf(String uid) async {
    final r = await conn.execute(
      Sql.named(
        'select consentimento_lgpd_versao from public.perfis where id = @u',
      ),
      parameters: {'u': uid},
    );
    return r.isEmpty ? null : r.first[0] as String?;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestUser(conn, uid);
      await seedLegacyProfile(uid);
    }
  });

  tearDownAll(() async {
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    '(a) FR-007/SC-002: a migration não preencheu nenhuma linha existente',
    () async {
      expect(await versionOf(_legacyUid), isNull);

      final r = await conn.execute(
        'select count(*) from public.perfis '
        'where consentimento_lgpd_aceito_em is not null '
        '  and consentimento_lgpd_versao is null',
      );
      expect((r.first[0] as int), greaterThanOrEqualTo(1),
          reason: 'aceite sem versão conhecida é um estado legítimo e '
              'permanente, não um dado faltando a ser preenchido');
    },
  );

  test(
    '(b) SC-002: backfill por cliente é impossível, não só desaconselhado',
    () async {
      // Duas camadas, e este teste hoje só alcança a de fora: desde a change
      // `endurecer-grant-update-perfis`, `consentimento_lgpd_versao` não tem
      // `grant update` para `authenticated` (nunca foi coluna gravável pela
      // titular — só o gatilho `perfis_carimbar_consentimento` a carimba), e
      // o Postgres recusa a cláusula `SET` antes mesmo de a linha existir
      // para o gatilho ver. `42501` é `permission denied`. Se um dia essa
      // coluna ganhasse `grant` por engano, o ramo `else` do gatilho ainda
      // restauraria o valor antigo — é a segunda camada, redundante de
      // propósito.
      await expectLater(
        asUser(conn, _legacyUid, () async {
          await conn.execute(
            Sql.named(
              "update public.perfis set consentimento_lgpd_versao = '1.1' "
              'where id = @u',
            ),
            parameters: {'u': _legacyUid},
          );
        }),
        throwsA(isA<ServerException>().having((e) => e.code, 'código', '42501')),
        reason: 'nem a própria pessoa consegue fabricar a própria versão',
      );

      expect(await versionOf(_legacyUid), isNull);
    },
  );

  test(
    '(c) Perfil antigo continua editável — não há constraint travando UPDATE',
    () async {
      // É o caminho que a feature 016 (Meu Perfil) vai usar. Se um
      // `check ... not valid` tivesse entrado, isto falharia.
      await asUser(conn, _legacyUid, () async {
        await conn.execute(
          Sql.named("update public.perfis set nome = 'Nome Corrigido' "
              'where id = @u'),
          parameters: {'u': _legacyUid},
        );
      });

      final r = await conn.execute(
        Sql.named('select nome from public.perfis where id = @u'),
        parameters: {'u': _legacyUid},
      );
      expect(r.first[0], 'Nome Corrigido');
      expect(await versionOf(_legacyUid), isNull);
    },
  );

  test(
    '(d) LGPD art. 18, VI: quem se cadastrou antes ainda consegue apagar a '
    'conta',
    () async {
      await asUser(conn, _legacyForDeleteUid, () async {
        await conn.execute('select public.excluir_minha_conta()');
      });

      final r = await conn.execute(
        Sql.named(
          'select nome, anonimizado_em is not null, '
          'consentimento_lgpd_aceito_em is not null, consentimento_lgpd_versao '
          'from public.perfis where id = @u',
        ),
        parameters: {'u': _legacyForDeleteUid},
      );

      expect(r.first[0], 'Membro removido');
      expect(r.first[1], isTrue);
      // A data do aceite sobrevive de propósito: é a prova da base legal do
      // histórico que a feature 009 conserva. E a versão continua nula, porque
      // apagar a conta não é aceitar texto nenhum.
      expect(r.first[2], isTrue);
      expect(r.first[3], isNull);
    },
  );
}

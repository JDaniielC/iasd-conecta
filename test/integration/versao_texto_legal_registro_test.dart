import 'package:iasd_conecta/features/legal/legal_metadata.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 017 — o guarda da duplicação declarada.
///
/// O número da versão do texto legal existe em dois lugares que não dá para
/// derivar um do outro: o TEXTO está compilado no binário do app
/// (`LegalMetadata.version`), e o catálogo `public.versoes_texto_legal` é o que
/// o banco carimba em cada consentimento.
///
/// Se os dois divergirem, o estrago é silencioso: todo cadastro novo é
/// carimbado com uma versão diferente da que a pessoa leu na tela. Este arquivo
/// existe para que publicar texto novo sem atualizar os dois lados quebre o
/// build em vez de gravar registro errado.

const _profileUid = '97000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _profileUid, name: 'Pessoa Versao');
  });

  tearDownAll(() async {
    await cleanUpTestUser(conn, _profileUid);
    await conn.close();
  });

  test(
    'FR-002: a versão vigente no banco é a mesma que o app exibe',
    () async {
      final r = await conn.execute('select public.versao_texto_legal_vigente()');
      final currentVersion = r.first[0] as String;

      expect(
        currentVersion,
        LegalMetadata.version,
        reason: 'publicar texto novo muda LegalMetadata.version E semeia a '
            'linha correspondente em public.versoes_texto_legal, no mesmo '
            'commit — se este teste falhou, só um dos dois foi feito, e todo '
            'cadastro novo está sendo carimbado com a versão errada',
      );
    },
  );

  test(
    'FR-004: o catálogo de versões não é escrito em runtime',
    () async {
      // Publicar versão é evento de release, não ação de aplicação. Sem grant,
      // nem o cliente autenticado alcança a tabela.
      for (final statement in [
        "insert into public.versoes_texto_legal (versao, vigente_desde) "
            "values ('9.9', now())",
        "update public.versoes_texto_legal set vigente_desde = now()",
        "delete from public.versoes_texto_legal",
      ]) {
        await expectLater(
          asUser(conn, _profileUid, () async {
            await conn.execute(statement);
          }),
          throwsA(isA<Exception>()),
          reason: 'recusado: $statement',
        );
      }
    },
  );

  test(
    'FR-002/SC-002: cliente que tenta gravar versão à mão é neutralizado pelo '
    'gatilho, antes mesmo de a FK opinar',
    () async {
      // A tarefa previa que a FK recusasse. Medido: ela nem chega a ser
      // consultada. O gatilho cai no ramo `else` (o `_aceito_em` não mudou),
      // restaura o valor antigo, e o update conclui sem erro — com a versão
      // intacta. É o resultado que SC-002 quer: backfill por cliente é
      // impossível, não só desaconselhado.
      await conn.execute(
        Sql.named(
          'update public.perfis set consentimento_lgpd_versao = @v '
          'where id = @u',
        ),
        parameters: {'v': '3.7-inexistente', 'u': _profileUid},
      );

      final r = await conn.execute(
        Sql.named(
          'select consentimento_lgpd_versao from public.perfis where id = @u',
        ),
        parameters: {'u': _profileUid},
      );
      expect(r.first[0], isNotNull,
          reason: 'o Perfil foi criado com o gatilho ativo, então tem versão');
      expect(r.first[0], LegalMetadata.version,
          reason: 'e continua sendo a que o banco carimbou, não a inventada');
    },
  );

  test(
    'FR-002: a FK existe e recusa versão fora do catálogo — provado com o '
    'gatilho desligado',
    () async {
      // O gatilho torna a FK inalcançável por qualquer caminho normal, o que é
      // bom mas também esconde se ela funciona. Desligá-lo é o único jeito de
      // provar que a segunda camada existe de verdade.
      //
      // Tudo numa transação com rollback: `alter table ... disable trigger`
      // toma ACCESS EXCLUSIVE e é GLOBAL. Fora de transação, o gatilho fica
      // desligado para todo mundo durante a janela, e `dart test` roda os
      // arquivos em paralelo — outro teste inserindo/atualizando Perfil nesse
      // instante gravaria sem carimbo (achado em 2026-08-11: derrubava
      // consentimentos_por_versao_test.dart e consentimento_versao_carimbada_
      // test.dart de forma intermitente). Dentro da transação o lock é
      // segurado até o rollback, que também desfaz o disable — dispensa
      // `enable trigger` explícito, inclusive quando o update abaixo lança e
      // aborta a transação.
      await conn.execute('begin');
      try {
        await conn.execute(
          'alter table public.perfis '
          'disable trigger perfis_carimbar_consentimento_trigger',
        );
        await expectLater(
          conn.execute(
            Sql.named(
              'update public.perfis set consentimento_lgpd_versao = @v '
              'where id = @u',
            ),
            parameters: {'v': '3.7-inexistente', 'u': _profileUid},
          ),
          throwsA(isA<Exception>()),
        );
      } finally {
        await conn.execute('rollback');
      }
    },
  );
}

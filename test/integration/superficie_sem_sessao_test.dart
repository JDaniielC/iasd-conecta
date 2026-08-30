import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `fechar-superficie-anon` — os dois lados do fechamento.
///
/// O inventário (`inventario_superficie_anon_test.dart`) olha o catálogo:
/// privilégio, papel da policy, grant. Este olha o COMPORTAMENTO, e nos dois
/// sentidos — sem o segundo, fechar tudo passaria no primeiro.
///
///   - sem sessão, a porta fecha;
///   - o Visitante, que TEM sessão, continua vendo o que via.
///
/// A distinção é a change inteira: `signInAnonymously` roda no arranque do app,
/// então quem não tem cadastro chega ao banco como `authenticated`. `anon` é a
/// requisição sem `Authorization` — `curl` com a chave publicável, ou o
/// arranque em que aquele login falhou. Ver `superficie-sem-login`.

const _uidOwner = 'fb000000-0000-0000-0000-000000000001';
const _uidVisitor = 'fb000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona FB');
    await createTestVisitor(conn, _uidVisitor);
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo FB');
    actionId = await createLooseAction(
      conn,
      creatorId: _uidOwner,
      name: 'Ação FB',
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  Future<int> countRows(String table, String column, String id) async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.$table where $column = @id'),
      parameters: {'id': id},
    );
    return r.first[0]! as int;
  }

  group('o Visitante continua enxergando o que via', () {
    // ESTE é o contrapeso, e sem ele o grupo de baixo passaria com o app
    // quebrado: fechar `anon` não pode ter fechado nada para quem tem sessão.
    // Cada linha aqui é uma tela que existe.

    test('vê o Grupo e a Ação', () async {
      expect(
        await asVisitor(
          conn,
          _uidVisitor,
          () => countRows('grupos', 'id', groupId),
        ),
        1,
      );
      expect(
        await asVisitor(
          conn,
          _uidVisitor,
          () => countRows('acoes', 'id', actionId),
        ),
        1,
      );
    });

    test('vê quem participa do Grupo', () async {
      // FR-006. O Dono entra por gatilho, então há pelo menos uma linha.
      expect(
        await asVisitor(
          conn,
          _uidVisitor,
          () => countRows('participacoes_grupo', 'grupo_id', groupId),
        ),
        greaterThan(0),
      );
    });

    test('vê as listas que o cadastro precisa', () async {
      // `igrejas` e `categorias_grupo` alimentam o formulário de cadastro, e
      // quem se cadastra ainda é Visitante quando o abre.
      await asVisitor(conn, _uidVisitor, () async {
        final churches = await conn.execute(
          'select count(*) from public.igrejas',
        );
        final categories = await conn.execute(
          'select count(*) from public.categorias_grupo',
        );
        expect(churches.first[0], greaterThan(0));
        expect(categories.first[0], greaterThan(0));
      });
    });

    test('alcança a versão do texto legal', () async {
      // A tela de consentimento é anterior ao cadastro, e o Visitante a lê.
      await asVisitor(conn, _uidVisitor, () async {
        final r = await conn.execute(
          'select count(*) from public.versoes_texto_legal',
        );
        expect(r.first[0], greaterThan(0));
      });
    });
  });

  group('sem sessão, a porta fecha', () {
    // A recusa aqui é por PRIVILÉGIO — `revoke select ... from anon` —, e por
    // isso vem como exceção e não como lista vazia.
    //
    // Isto NÃO reabre o oráculo por forma de resposta que
    // `SECURITY-AUDIT.md` registra: lá a distinção que importava era entre
    // "não existe" e "não posso ver" DENTRO de uma tabela que a pessoa
    // alcança. Aqui a tabela inteira é inalcançável, para qualquer id, então
    // o error não conta nada que a ausência não contasse.

    for (final table in [
      'grupos',
      'acoes',
      'participacoes_grupo',
      'confirmacoes_acao',
      'administradores_distrito',
      'liderancas',
      'mudancas',
      'votos',
      // Change `observador-de-retencao`: nasceu fechada como as demais —
      // `anon` sem grant nenhum, e o único braço da RLS é o Administrador.
      'execucoes_de_faxina',
    ]) {
      test('$table é inalcançável', () async {
        Object? error;
        try {
          await asAnon(
            conn,
            () => conn.execute('select count(*) from public.$table'),
          );
        } catch (e) {
          error = e;
        }
        expect(error, isA<ServerException>(), reason: table);
      });
    }

    test('as três funções que perderam o PUBLIC recusam', () async {
      for (final call in [
        "public.nome_valido('Maria Silva')",
        'public.autor_de_mudanca()',
        'public.versao_texto_legal_vigente()',
      ]) {
        Object? error;
        try {
          await asAnon(conn, () => conn.execute('select $call'));
        } catch (e) {
          error = e;
        }
        expect(error, isA<ServerException>(), reason: call);
      }
    });

    test('`fechar_rodada_se_devido` não é mais disparável sem login', () async {
      // A pior das seis: `security definer`, ESCREVE, e o caminho de fechar
      // Rodada vencida não confere `auth.uid()`. Qualquer pessoa com `curl` e
      // a chave publicável fechava Rodada vencida de qualquer Grupo.
      Object? error;
      try {
        await asAnon(
          conn,
          () => conn.execute(
            "select public.fechar_rodada_se_devido("
            "'00000000-0000-0000-0000-000000000000'::uuid, false)",
          ),
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<ServerException>());
    });
  });

  test('o oráculo da lista de palavras fechou', () async {
    // Medido em 2026-08-16, ANTES desta change: `nome_valido` era `security
    // definer` e nascera sem grant nenhum, herdando `execute` de PUBLIC. A
    // tabela `palavras_bloqueadas` tem RLS sem policy — leitura direta por
    // `anon` dá 42501 —, mas a função aceitava a pergunta. Sondando como
    // `anon`: 'idiota' -> false, 'burro' -> false, 'estupido' -> false,
    // 'Maria Silva' -> true. Cinco palavras, quatro chamadas.
    //
    // A tabela recusar leitura direta não protege nada enquanto a função
    // responder a quem quer que pergunte: sonda-se um termo por chamada e a
    // lista sai inteira.
    final words = await conn.execute(
      'select palavra from public.palavras_bloqueadas limit 1',
    );
    final word = words.single[0]! as String;

    Object? error;
    try {
      await asAnon(
        conn,
        () => conn.execute(
          Sql.named('select public.nome_valido(@p)'),
          parameters: {'p': word},
        ),
      );
    } catch (e) {
      error = e;
    }
    expect(
      error,
      isA<ServerException>(),
      reason:
          'se isto voltar a devolver `false` em vez de recusar, o oráculo '
          'reabriu — é `false` que entrega que o termo está na lista',
    );

    // E continua respondendo a quem o app autoriza: a validação de nome no
    // cadastro depende dela, e quem se cadastra tem sessão.
    expect(
      await asVisitor(
        conn,
        _uidVisitor,
        () async => (await conn.execute(
          Sql.named('select public.nome_valido(@p)'),
          parameters: {'p': word},
        )).first[0],
      ),
      isFalse,
      reason: 'a lista continua sendo aplicada para quem tem sessão',
    );
  });
}

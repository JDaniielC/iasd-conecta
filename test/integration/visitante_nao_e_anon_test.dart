import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `separar-visitante-de-anon` — os dois papéis, lado a lado, no MESMO
/// cenário.
///
/// Os 27 pontos varridos por esta change provam cada um a sua regra, e nenhum
/// deles prova a DIFERENÇA. Sem este arquivo, alguém volta a escrever
/// `set role anon` num teste chamado "Visitante", tudo continua verde, e a
/// confusão renasce — foi assim que ela durou de 2026-07-23 a 2026-08-16.
///
/// A diferença, em uma frase: o app faz `signInAnonymously` no arranque
/// (`lib/core/supabase_client.dart`), antes de `runApp`. Todo Visitante chega
/// ao banco como `authenticated`, com `auth.uid()` preenchido e sem linha em
/// `perfis`. `anon` é a requisição que chega sem `Authorization` — e o app só
/// cai nela se aquele login falhar, estado em que a Home é estática.

// `fa`, e chegar nele custou duas tentativas — `f7` colidia com
// `notificacao_acao_cancelada_test` e `f9` com `notificacao_anonimizacao_test`.
// A suíte roda os arquivos em paralelo contra o mesmo banco, e uid repetido faz
// o `cleanUpTestUser` de um apagar o Perfil que o outro está usando.
//
// A lição, mais útil que o prefixo: NÃO se escolhe uid de olho. A consulta que
// lista os 60 prefixos já usados está na convergência 4 desta change, e havia
// 18 colisões na suíte quando ela rodou. Medido em 2026-08-16.
const _uidOwner = 'fa000000-0000-0000-0000-000000000001';
const _uidVisitor = 'fa000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona FA');
    await createTestVisitor(conn, _uidVisitor);
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo FA');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  Future<int> visibleNotifications() async {
    final r = await conn.execute('select count(*) from public.notificacoes');
    return r.first[0]! as int;
  }

  test('a mesma pergunta, dois TIPOS de não', () async {
    // O contraste é o teste. Se um dia as duas respostas coincidirem, é porque
    // alguém fundiu os papéis — e aí este arquivo fica vermelho antes de a
    // confusão se espalhar por 21 arquivos outra vez.
    //
    // `notificacoes` é o alvo porque ela sempre separou os dois: `anon` não tem
    // `grant`, e o Visitante tem — e a policy é que decide o que ele lê. É a
    // distinção que a spec chama de "recusa que acontece antes da regra".
    //
    // `grupos` era o contraste ÓBVIO e não servia quando este arquivo nasceu:
    // `anon` lia `grupos` exatamente como o Visitante, porque a policy ainda o
    // endereçava. A asserção ficou registrada como devida à change seguinte, e
    // ela entrou — `grupos` é o segundo caso, logo abaixo.
    expect(
      await asVisitor(conn, _uidVisitor, visibleNotifications),
      0,
      reason: 'o Visitante ALCANÇA a tabela; a policy é que devolve vazio',
    );

    Object? withoutSession;
    try {
      await asAnon(conn, visibleNotifications);
    } catch (e) {
      withoutSession = e;
    }
    expect(
      withoutSession,
      isA<ServerException>(),
      reason: 'sem sessão a barreira é o `grant`, uma camada antes da policy',
    );
  });

  test('e em `grupos` também, desde `fechar-superficie-anon`', () async {
    // O caso que este arquivo prometeu e não podia cumprir quando nasceu. A
    // policy `grupos_select_public` endereçava `anon, authenticated`, então os
    // dois liam igual e o contraste não existia.
    //
    // Agora ela endereça só `authenticated`, e o `grant select` saiu de `anon`:
    // o Visitante lê, quem não tem sessão nem alcança a tabela.
    expect(
      await asVisitor(conn, _uidVisitor, () async {
        final r = await conn.execute(
          Sql.named('select count(*) from public.grupos where id = @g'),
          parameters: {'g': groupId},
        );
        return r.first[0];
      }),
      1,
    );

    Object? erro;
    try {
      await asAnon(
        conn,
        () => conn.execute('select count(*) from public.grupos'),
      );
    } catch (e) {
      erro = e;
    }
    expect(
      erro,
      isA<ServerException>(),
      reason:
          'sem sessão a tabela é inalcançável — se isto voltar a devolver '
          'número, a superfície sem login reabriu',
    );
  });

  test('o Visitante tem auth.uid(); sem sessão não tem', () async {
    // A diferença mecânica por baixo de tudo, medida em vez de afirmada.
    final fromVisitor = await asVisitor(
      conn,
      _uidVisitor,
      () async => (await conn.execute('select auth.uid()')).first[0],
    );
    expect(fromVisitor.toString(), _uidVisitor);

    final withoutSession = await asAnon(
      conn,
      () async => (await conn.execute('select auth.uid()')).first[0],
    );
    expect(withoutSession, isNull);
  });

  test('asAnon não herda a identidade de quem rodou antes', () async {
    // Convergência 3. `reset role` NÃO limpa GUC customizado, e 16 das 48
    // cópias locais de `asUser` na suíte só fazem `reset role` — medido na
    // convergência 1. Sem limpar os claims ao ENTRAR, `asAnon` rodava como
    // `anon` com o `sub` da pessoa anterior, e um teste que diz provar "sem
    // sessão" provava "papel anon com a identidade de outra pessoa".
    //
    // Medido antes do conserto: `auth.uid()` dentro de `asAnon` devolvia
    // `fd000000-...-0001` em vez de nulo.
    //
    // A sujeira é reproduzida DE PROPÓSITO aqui — é o cenário real, não um
    // caso construído: é literalmente o que aqueles 16 arquivos deixam.
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to "
      "'{\"sub\":\"$_uidOwner\",\"role\":\"authenticated\"}'",
    );
    await conn.execute('reset role');

    final insideAnon = await asAnon(
      conn,
      () async => (await conn.execute('select auth.uid()')).first[0],
    );
    expect(
      insideAnon,
      isNull,
      reason:
          'sem sessão é sem identidade — herdar o `sub` anterior faz o '
          'teste medir a policy de outra pessoa',
    );

    // E não deixa sujeira para quem vem depois.
    final afterwards = await conn.execute(
      "select current_setting('request.jwt.claims', true)",
    );
    expect(afterwards.first[0], anyOf(isNull, isEmpty));
  });

  test('o Visitante de teste é anônimo de verdade — is_anonymous', () async {
    // `createTestVisitor` grava `is_anonymous = true`, e a coluna NÃO é
    // enfeite: `declarar_lideranca` (20260724100000:27), o gatilho de
    // Administrador (20260724092132:31) e o convite (20260813140000:66) leem
    // ela para decidir. Um Visitante de teste com `false` seria um Usuário com
    // Conta sem Perfil — pessoa que o app não produz — e passaria em regra que
    // o Visitante real não passa.
    final r = await conn.execute(
      Sql.named('select is_anonymous from auth.users where id = @u'),
      parameters: {'u': _uidVisitor},
    );
    expect(r.first[0], isTrue);

    // E a regra que lê a coluna recusa mesmo. `declarar_lideranca` exige Conta.
    Object? error;
    try {
      await asVisitor(conn, _uidVisitor, () async {
        await conn.execute(
          Sql.named('select public.declarar_lideranca(@g, 2026)'),
          parameters: {'g': groupId},
        );
      });
    } catch (e) {
      error = e;
    }
    expect(
      error,
      isA<ServerException>(),
      reason: 'sem Conta não se declara Líder, e é a coluna que decide',
    );
  });
}

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `filtro-e-intervalo-de-mensagem`, tarefas 4.6 a 4.10 — o RITMO.
///
/// Tudo escreve pela sessão de verdade (`asUser`), sem `createdAtOffset`: é o
/// único jeito de o relógio do teste ser o relógio do gatilho. `seedMessage`
/// recua o `created_at` uma hora justamente para NÃO tropeçar nesta regra, e
/// usá-lo aqui esvaziaria o arquivo inteiro sem falhar.
///
/// PACIÊNCIA DE PROPÓSITO. O intervalo é de 3 segundos, e provar que ele
/// libera exige esperar 3 segundos de verdade. Não há atalho honesto: mexer no
/// `created_at` da mensagem anterior seria testar um cenário que o app não
/// produz, e mexer na constante do banco seria testar outro número que não o
/// que está em produção.

const _uidAuthor = 'd6000000-0000-0000-0000-000000000001';
const _uidOther = 'd6000000-0000-0000-0000-000000000002';
const _allUids = [_uidAuthor, _uidOther];

/// Os mesmos números da migration. Lidos DELA em `5.2`; aqui repetidos como
/// literal de propósito — um teste que lesse a constante do banco passaria com
/// qualquer valor, inclusive zero.
const _minimumInterval = Duration(seconds: 3);
const _ceiling = 20;

void main() {
  late Connection conn;
  late String groupId;
  late String otherGroupId;

  Future<Object?> attempt(String uid, Future<void> Function() action) async {
    try {
      await asUser(conn, uid, action);
      return null;
    } catch (e) {
      return e;
    }
  }

  Future<Object?> write(String groupTarget, {String text = 'combinado'}) =>
      attempt(
        _uidAuthor,
        () => writeMessage(
          conn,
          authorId: _uidAuthor,
          groupId: groupTarget,
          text: text,
        ),
      );

  Future<int> countIn(String groupTarget) async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupTarget},
    );
    return r.first[0]! as int;
  }

  Future<void> clearAll() async {
    for (final g in [groupId, otherGroupId]) {
      await conn.execute(
        Sql.named('delete from public.mensagens where grupo_id = @g'),
        parameters: {'g': g},
      );
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: 30,
      );
    }
    groupId = await createGroup(conn, ownerId: _uidAuthor, name: 'Grupo AG');
    otherGroupId = await createGroup(
      conn,
      ownerId: _uidAuthor,
      name: 'Grupo AG vizinho',
    );
    await joinGroup(conn, groupId, _uidOther);
    await joinGroup(conn, otherGroupId, _uidOther);
  });

  tearDown(clearAll);

  tearDownAll(() async {
    await clearAll();
    for (final g in [groupId, otherGroupId]) {
      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': g},
      );
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('4.6 a segunda mensagem antes do intervalo é recusada', () async {
    expect(await write(groupId), isNull);

    final error = await write(groupId, text: 'e mais uma');
    expect(error, isA<ServerException>());
    expect((error! as ServerException).code, 'PT425');

    // A PRIMEIRA CONTINUA GRAVADA. Sem esta linha, um gatilho que abortasse a
    // transação inteira passaria no caso acima — e a pessoa perderia o que já
    // tinha dito por ter falado rápido demais.
    expect(await countIn(groupId), 1);
  });

  test('4.6 a recusa diz QUANTO falta, e o número é usável', () async {
    await write(groupId);
    final error = (await write(groupId))! as ServerException;

    final remaining = int.parse(error.hint!);
    expect(remaining, greaterThan(0));
    expect(
      remaining,
      lessThanOrEqualTo(_minimumInterval.inSeconds),
      reason: 'faltar mais do que o intervalo inteiro seria conta errada',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('4.6 depois do intervalo a segunda passa', () async {
    expect(await write(groupId), isNull);
    await Future<void>.delayed(_minimumInterval + const Duration(seconds: 1));
    expect(await write(groupId, text: 'agora sim'), isNull);
    expect(await countIn(groupId), 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('4.6 o intervalo de um chat não conta no outro', () async {
    // Conversar em dois Grupos ao mesmo tempo é uso normal, e um limite global
    // puniria isso. As duas escritas são imediatamente seguidas.
    expect(await write(groupId), isNull);
    expect(await write(otherGroupId), isNull);
    expect(await countIn(groupId), 1);
    expect(await countIn(otherGroupId), 1);
  });

  test('4.7 o teto barra a mensagem seguinte, mesmo respeitando o intervalo', () async {
    // Encher a janela sem esperar 3 s vinte vezes: as 20 primeiras entram como
    // histórico recuado — dentro da janela de 5 minutos, longe do intervalo de
    // 3 s. É o cenário do requisito: "todas respeitando o intervalo mínimo".
    for (var i = 0; i < _ceiling; i++) {
      await writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'mensagem $i',
        // 10 s de distância entre elas: acima do intervalo, dentro da janela.
        createdAtOffset: Duration(seconds: 10 * (_ceiling - i)),
      );
    }
    expect(await countIn(groupId), _ceiling);

    final error = await write(groupId, text: 'a vigésima primeira');
    expect(error, isA<ServerException>());
    final e = error! as ServerException;
    expect(
      e.code,
      'PT429',
      reason: 'teto e intervalo são causas diferentes e códigos diferentes',
    );
    expect(int.parse(e.hint!), greaterThan(0), reason: 'diz quando libera');
    expect(await countIn(groupId), _ceiling);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('4.7 quando a janela desliza, volta a aceitar', () async {
    // Mesmas 20, mas a mais antiga já saiu da janela de 5 minutos. A contagem
    // dentro da janela cai para 19, e a próxima entra.
    for (var i = 0; i < _ceiling; i++) {
      await writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'mensagem $i',
        createdAtOffset: i == 0
            ? const Duration(minutes: 6)
            : Duration(seconds: 10 * (_ceiling - i)),
      );
    }

    expect(
      await write(groupId, text: 'depois que a janela deslizou'),
      isNull,
      reason: 'com a mais antiga fora da janela sobram 19, e cabe mais uma',
    );
    expect(await countIn(groupId), _ceiling + 1);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('o expurgo da Ação zera o limite daquele chat', () async {
    // CONVERGENCE 1. O cenário estava escrito na spec — "Mensagens do chat
    // foram expurgadas" — e nenhum teste o exercitava.
    //
    // É a consequência ACEITA do desenho de não guardar nada: a contagem sai do
    // `created_at` das mensagens que existem, então quando elas deixam de
    // existir o limite não tem o que contar. A spec declara isso aceitável —
    // "chat expirado não é chat que se possa encher" —, e uma consequência
    // declarada sem prova é uma frase.
    //
    // Ação AVULSA e com data no passado: `expurgar_mensagens_de_acao` apaga por
    // `acoes.data_hora + 30 dias`, não por quando a mensagem foi escrita.
    final expiredAction = await createLooseAction(
      conn,
      creatorId: _uidAuthor,
      name: 'Ação AG expirada ${_ceiling}x',
      interval: "interval '-31 days'",
    );

    try {
      for (var i = 0; i < _ceiling; i++) {
        await writeMessage(
          conn,
          authorId: _uidAuthor,
          actionId: expiredAction,
          text: 'mensagem $i',
          createdAtOffset: Duration(seconds: 10 * (_ceiling - i)),
        );
      }

      final blocked = await attempt(
        _uidAuthor,
        () => writeMessage(
          conn,
          authorId: _uidAuthor,
          actionId: expiredAction,
          text: 'a que passa do teto',
        ),
      );
      expect(
        (blocked! as ServerException).code,
        'PT429',
        reason: 'o teto está valendo ANTES do expurgo — sem isto o caso não '
            'distingue "o limite zerou" de "o limite nunca pegou"',
      );

      final purged = await conn.execute(
        'select public.expurgar_mensagens_de_acao()',
      );
      expect(
        purged.first[0]! as int,
        greaterThanOrEqualTo(_ceiling),
        reason: 'o expurgo apagou as mensagens desta Ação',
      );

      expect(
        await attempt(
          _uidAuthor,
          () => writeMessage(
            conn,
            authorId: _uidAuthor,
            actionId: expiredAction,
            text: 'depois do expurgo',
          ),
        ),
        isNull,
        reason: 'sem o que contar, o limite volta a permitir',
      );
    } finally {
      await conn.execute(
        Sql.named('delete from public.mensagens where acao_id = @a'),
        parameters: {'a': expiredAction},
      );
      await conn.execute("set app.bypass_acoes_protecao to 'true'");
      await conn.execute(
        Sql.named('delete from public.acoes where id = @a'),
        parameters: {'a': expiredAction},
      );
      await conn.execute('reset app.bypass_acoes_protecao');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('4.8 chamada direta, sem passar pela tela, é recusada igual', () async {
    // O limite vale NO BANCO. Aqui não há tela nenhuma — é `insert` cru pela
    // sessão, que é exatamente o que uma chamada direta à API do PostgREST
    // vira do outro lado.
    expect(await write(groupId, text: 'primeira direta'), isNull);
    for (final text in ['segunda direta', 'terceira direta']) {
      final error = await write(groupId, text: text);
      expect((error! as ServerException).code, 'PT425', reason: text);
    }
    expect(await countIn(groupId), 1);
  });

  test('4.9 duas escritas simultâneas gravam exatamente uma', () async {
    // SEM A TRAVA ESTE É O CASO QUE PASSA AS DUAS: as duas transações leem o
    // mesmo `max(created_at)` — nenhuma —, as duas concluem que está liberado,
    // e as duas gravam. O `for update` na linha de `perfis` do autor põe a
    // segunda na fila até a primeira comitar.
    final second = await openTestConnection();
    try {
      Future<Object?> writeOn(Connection c) async {
        try {
          await c.execute('set role authenticated');
          await c.execute(
            "set request.jwt.claims to "
            "'{\"sub\":\"$_uidAuthor\",\"role\":\"authenticated\"}'",
          );
          await c.execute('begin');
          await writeMessage(
            c,
            authorId: _uidAuthor,
            groupId: groupId,
            text: 'simultânea',
          );
          await c.execute('commit');
          return null;
        } catch (e) {
          try {
            await c.execute('rollback');
          } catch (_) {}
          return e;
        } finally {
          await c.execute('reset role');
          await c.execute('reset request.jwt.claims');
        }
      }

      final results = await Future.wait([writeOn(conn), writeOn(second)]);

      expect(
        results.where((r) => r == null).length,
        1,
        reason: 'exatamente uma passa',
      );
      final refused = results.whereType<ServerException>().single;
      expect(refused.code, 'PT425');
      expect(await countIn(groupId), 1);
    } finally {
      await second.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('4.10 as três causas devolvem três códigos distintos', () async {
    // Um a um, e o ponto é a DISTINÇÃO: se as três recusas viessem com o mesmo
    // código, a tela precisaria interpretar o texto do erro para saber o que
    // dizer — e texto de erro se reescreve sem ninguém notar.
    await lockBlockedWordList(conn);
    const word = 'zubixo';
    await conn.execute(
      Sql.named(
        'insert into public.palavras_bloqueadas_mensagem (palavra) values (@p) '
        'on conflict do nothing',
      ),
      parameters: {'p': word},
    );

    try {
      final byWord =
          (await write(groupId, text: 'seu $word'))! as ServerException;
      expect(byWord.code, 'PT422');
      expect(byWord.hint, word);
      expect(await countIn(groupId), 0, reason: 'o filtro roda ANTES do ritmo');

      expect(await write(groupId, text: 'limpa'), isNull);
      final byInterval = (await write(groupId))! as ServerException;
      expect(byInterval.code, 'PT425');

      await conn.execute(
        Sql.named('delete from public.mensagens where grupo_id = @g'),
        parameters: {'g': groupId},
      );
      for (var i = 0; i < _ceiling; i++) {
        await writeMessage(
          conn,
          authorId: _uidAuthor,
          groupId: groupId,
          text: 'mensagem $i',
          createdAtOffset: Duration(seconds: 10 * (_ceiling - i)),
        );
      }
      final byCeiling = (await write(groupId))! as ServerException;
      expect(byCeiling.code, 'PT429');

      expect({byWord.code, byInterval.code, byCeiling.code}, hasLength(3));
    } finally {
      await conn.execute(
        Sql.named(
          'delete from public.palavras_bloqueadas_mensagem where palavra = @p',
        ),
        parameters: {'p': word},
      );
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('3.4 nenhum dos gatilhos escreve em tabela nenhuma', () async {
    // Nenhum contador, nenhuma tabela de tentativa, nenhum log: a contagem sai
    // do `created_at` das mensagens que existem. Contador de tentativa é dado
    // de COMPORTAMENTO — quando esta pessoa tentou falar e quantas vezes —, e o
    // projeto já recusou por escrito criar dado desse tipo por conveniência
    // (`lib/features/news/data/news_repository.dart:7-16`).
    //
    // A prova olha o CORPO das funções, e não a contagem de linhas do banco.
    // Contar linhas antes e depois seria não determinístico: `dart test` roda
    // os arquivos em paralelo contra o mesmo Postgres, e outro arquivo
    // escrevendo no meio da medição reprovaria este caso sem nada de errado
    // ter acontecido. O corpo da função não muda por concorrência.
    final rows = await conn.execute('''
      select p.proname, p.prosrc
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('mensagens_ritmo_de_envio',
                          'mensagens_filtro_de_palavra',
                          'denuncias_mensagem_filtro_de_palavra')
      order by 1
    ''');
    expect(rows, hasLength(3), reason: 'os três gatilhos desta change existem');

    for (final row in rows) {
      final name = row[0]! as String;
      // `for update` sai antes da busca: é a TRAVA do ritmo, não uma escrita.
      // Sem tirá-la, a palavra `update` dentro dela reprovaria o caso certo.
      final body = (row[1]! as String)
          .toLowerCase()
          .replaceAll(RegExp(r'for\s+update'), ' ');

      for (final verb in ['insert', 'delete', 'truncate', 'update', 'copy']) {
        expect(
          RegExp('\\b$verb\\b').hasMatch(body),
          isFalse,
          reason: '$name tem `$verb` no corpo — a recusa passou a deixar rastro',
        );
      }
    }
  });
}

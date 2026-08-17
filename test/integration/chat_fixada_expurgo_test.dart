import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `mensagem-fixada` — a EXCEÇÃO ao prazo de 30 dias, e o que a desfaz.
///
/// Este é o arquivo de peso da change. A partir daqui, "as mensagens da Ação
/// são apagadas em 30 dias" é falso sem ressalva: a promessa vira "30 dias,
/// salvo o que estiver fixado, com teto de 3 por chat". O que se prova aqui é
/// que a exceção é a declarada — nem mais estreita, nem mais larga.
///
/// Quatro caminhos DESFAZEM a exceção, e cada um por um motivo diferente:
///   desfixar à mão (a vencida sai no expurgo seguinte, sem carência nova),
///   remoção por moderação, exclusão de conta do autor, e o teto — que impede
///   que fixar vire uma forma de desligar a retenção da conversa inteira.
///
/// CUIDADO AO MEXER: `expurgar_mensagens_de_acao()` é GLOBAL — varre a tabela
/// inteira, não só as linhas deste arquivo, e `dart test` roda os arquivos em
/// paralelo. Por isso toda asserção é sobre linha identificada por id, nunca
/// sobre o número que a função devolve.

const _uidCreator = 'fb000000-0000-0000-0000-000000000001';
const _uidOwner = 'fb000000-0000-0000-0000-000000000002';
const _uidMember = 'fb000000-0000-0000-0000-000000000003';
const _uidLeaver = 'fb000000-0000-0000-0000-000000000004';
const _allUids = [_uidCreator, _uidOwner, _uidMember, _uidLeaver];

void main() {
  late Connection conn;
  late String expiredAction, groupId;

  Future<bool> exists(String messageId) async {
    final r = await conn.execute(
      Sql.named('select 1 from public.mensagens where id = @m'),
      parameters: {'m': messageId},
    );
    return r.isNotEmpty;
  }

  Future<void> purge() async {
    await conn.execute('select public.expurgar_mensagens_de_acao()');
  }

  Future<int> pinAs(String uid, String messageId) => asUser(
    conn,
    uid,
    () => pinMessage(conn, uid: uid, messageId: messageId),
  );

  /// Ver a nota em `chat_fixada_test.dart`: cada teste semeia o que precisa, e
  /// desfixar como `postgres` não passa pelo gatilho.
  setUp(() async {
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where acao_id = @a or grupo_id = @g',
      ),
      parameters: {'a': expiredAction, 'g': groupId},
    );
  });

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
    // O criador da Ação é a autoridade dela — é ele quem fixa aqui.
    expiredAction = await createLooseAction(
      conn,
      creatorId: _uidCreator,
      name: 'Ação FB de 31 dias atrás',
      interval: "interval '-31 days'",
    );
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo FB');
    for (final uid in [_uidMember, _uidLeaver]) {
      await joinGroup(conn, groupId, uid);
    }
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where acao_id = @a or grupo_id = @g',
      ),
      parameters: {'a': expiredAction, 'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': expiredAction},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @u'),
      parameters: {'u': _uidOwner},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('4.5 — a fixada fica, o resto da Ação vencida sai', () async {
    final pinned = await seedMessage(
      conn,
      authorId: _uidCreator,
      actionId: expiredAction,
      text: 'o endereço é na frente da igreja',
    );
    final ordinary = [
      for (var i = 0; i < 2; i++)
        await seedMessage(
          conn,
          authorId: _uidCreator,
          actionId: expiredAction,
          text: 'bate-papo que expira',
        ),
    ];
    expect(await pinAs(_uidCreator, pinned), 1);

    final before = await conn.execute(
      Sql.named('select count(*) from public.mensagens where acao_id = @a'),
      parameters: {'a': expiredAction},
    );
    expect(before.first[0], 3, reason: 'a contagem ANTES é o outro lado da prova');

    await purge();

    final after = await conn.execute(
      Sql.named('select count(*) from public.mensagens where acao_id = @a'),
      parameters: {'a': expiredAction},
    );
    expect(after.first[0], 1);
    expect(await exists(pinned), isTrue);
    for (final id in ordinary) {
      expect(await exists(id), isFalse);
    }
  });

  test('4.6 — desfixar depois do prazo apaga no expurgo seguinte, sem carência',
      () async {
    final id = await seedMessage(
      conn,
      authorId: _uidCreator,
      actionId: expiredAction,
      text: 'já venceu, mas está fixada',
    );
    await pinAs(_uidCreator, id);
    await purge();
    expect(await exists(id), isTrue, reason: 'a fixação segurou');

    // Nenhum prazo novo começa a contar: o `where` do expurgo olha o estado de
    // agora, não a história dele. É o comportamento que a spec exige, e ele cai
    // fora do desenho — não precisou de código.
    await asUser(conn, _uidCreator, () => unpinMessage(conn, messageId: id));
    await purge();
    expect(await exists(id), isFalse);
  });

  test('4.7 — remoção por moderação desfixa e libera a vaga', () async {
    final ids = [
      for (var i = 0; i < 3; i++)
        await seedMessage(
          conn,
          authorId: _uidMember,
          groupId: groupId,
          text: 'combinação do Grupo',
        ),
    ];
    for (final id in ids) {
      expect(await pinAs(_uidOwner, id), 1);
    }
    expect(await pinnedCountIn(conn, groupId: groupId), 3);

    final spare = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'a que quer a vaga',
    );
    // Com o teto cheio, esta é recusada — é o que dá sentido ao resto do teste.
    expect(
      () => pinAs(_uidOwner, spare),
      throwsA(
        isA<ServerException>().having((e) => e.code, 'code', 'PT409'),
      ),
    );

    final removed = await asUser(conn, _uidOwner, () async {
      final r = await conn.execute(
        Sql.named(
          'update public.mensagens set texto = null, removida_em = now(), '
          'removida_por = @u where id = @m',
        ),
        parameters: {'m': ids[0], 'u': _uidOwner},
      );
      return r.affectedRows;
    });
    expect(removed, 1);

    // Lápide fixada no topo do chat ocupa vaga do teto e não informa nada.
    final state = await pinnedStateOf(conn, ids[0]);
    expect(state.pinned, isFalse);
    expect(state.pinnedBy, isNull);
    expect(await pinnedCountIn(conn, groupId: groupId), 2);

    expect(await pinAs(_uidOwner, spare), 1);
  });

  test('4.8 — excluir a conta esvazia o texto E desfixa, na mesma transação',
      () async {
    final id = await seedMessage(
      conn,
      authorId: _uidLeaver,
      groupId: groupId,
      text: 'sou a Fulana e levo o som',
    );
    expect(await pinAs(_uidOwner, id), 1);

    // Uma chamada só. `excluir_minha_conta` NÃO ganhou linha nova nesta change:
    // o `update ... set texto = null` que ela já fazia dispara o desfixe dentro
    // do próprio gatilho, na mesma linha e na mesma transação.
    await asUser(
      conn,
      _uidLeaver,
      () => conn.execute('select public.excluir_minha_conta()'),
    );

    final message = await messageStateOf(conn, id);
    expect(message.hasText, isFalse);
    expect(
      message.removed,
      isFalse,
      reason: 'lápide de conta excluída, não de moderação — são fatos diferentes',
    );
    final pin = await pinnedStateOf(conn, id);
    expect(pin.pinned, isFalse);
    expect(pin.pinnedBy, isNull);
    expect(await pinnedCountIn(conn, groupId: groupId), 0);
  });

  test('4.9 — mensagem de Grupo fixada não é alcançada pelo expurgo', () async {
    // Chat de Grupo NUNCA expira — o expurgo junta com `acoes` e mensagem de
    // Grupo tem `acao_id` nulo. A condição nova (`fixada_em is null`) não podia
    // ter introduzido caminho para lá, e este teste é o que diz isso em voz
    // alta em vez de presumir pela leitura.
    final pinned = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'fixada no Grupo',
    );
    final loose = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'não fixada no Grupo',
    );
    expect(await pinAs(_uidOwner, pinned), 1);

    await purge();

    expect(await exists(pinned), isTrue);
    expect(await exists(loose), isTrue);
  });
}

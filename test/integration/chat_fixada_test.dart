import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `mensagem-fixada` — quem fixa, quem desfixa, e quantas cabem.
///
/// AS DUAS FORMAS DE RECUSA aparecem juntas aqui, e a diferença não é detalhe:
///
///   - Quem **nem passa pela policy** `mensagens_update_autor_ou_autoridade`
///     — o participante comum, o dono de outro Grupo — leva ZERO LINHA. No
///     Postgres, policy que recusa não levanta exceção: a linha deixa de
///     existir para aquela sessão. A asserção é `affectedRows`.
///   - Quem **passa pela policy e é barrado pelo gatilho** — o autor, que a
///     policy deixa entrar pelo braço dele — leva exceção com `errcode`. A
///     asserção é `throwsA`.
///
/// Um teste que esperasse exceção nos dois casos passaria pelo motivo errado na
/// metade deles. Ver a seção "Recusa de RLS é ausência, não erro" em CLAUDE.md.
///
/// FIXAR TIRA A MENSAGEM DO PRAZO DE 30 DIAS, e é por isso que a autoridade
/// aqui é mais estreita que a de escrever: participante comum não fixa nem a
/// própria mensagem. O expurgo é provado em `chat_fixada_expurgo_test.dart`.

const _uidOwner = 'fa000000-0000-0000-0000-000000000001';
const _uidAuthor = 'fa000000-0000-0000-0000-000000000002';
const _uidMember = 'fa000000-0000-0000-0000-000000000003';
const _uidAdmin = 'fa000000-0000-0000-0000-000000000004';
const _uidOtherGroupOwner = 'fa000000-0000-0000-0000-000000000005';
const _uidOutsider = 'fa000000-0000-0000-0000-000000000006';
const _uidMinor = 'fa000000-0000-0000-0000-000000000007';
const _allUids = [
  _uidOwner,
  _uidAuthor,
  _uidMember,
  _uidAdmin,
  _uidOtherGroupOwner,
  _uidOutsider,
  _uidMinor,
];

void main() {
  late Connection conn;
  late String groupId, otherGroup, looseActionId;

  /// Fixa como [uid] e devolve o erro, ou nulo quando não houve exceção.
  /// Zero linha afetada NÃO é erro — é o outro caminho de recusa, e quem quer
  /// medi-lo usa [pinMessage] direto.
  Future<Object?> pinAs(String uid, String messageId) async {
    try {
      await asUser(
        conn,
        uid,
        () => pinMessage(conn, uid: uid, messageId: messageId),
      );
      return null;
    } catch (e) {
      return e;
    }
  }

  Future<int> pinRowsAs(String uid, String messageId) => asUser(
    conn,
    uid,
    () => pinMessage(conn, uid: uid, messageId: messageId),
  );

  Future<String> seed({String? group, String? action}) => seedMessage(
    conn,
    authorId: _uidAuthor,
    groupId: group,
    actionId: action,
    text: 'combinação que precisa sobreviver',
  );

  /// Apaga a conversa dos espaços DESTE arquivo entre um teste e outro.
  ///
  /// Apagar e não desfixar: desfixar como `postgres` não passa pelo gatilho —
  /// sem sessão, `auth.uid()` é nulo e ninguém tem autoridade. Cada teste
  /// semeia o que precisa, então a lista vazia é o começo certo, e a limpeza
  /// é por espaço deste arquivo — nunca por padrão que outro arquivo case.
  Future<void> clearChats() async {
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where grupo_id = any(@gs::uuid[]) '
        'or acao_id = @a',
      ),
      parameters: {
        'gs': [groupId, otherGroup],
        'a': looseActionId,
      },
    );
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: uid == _uidMinor ? 15 : 30,
      );
    }
    await createTestDistrictAdmin(conn, _uidAdmin);

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo FA');
    for (final uid in [_uidAuthor, _uidMember, _uidMinor]) {
      await joinGroup(conn, groupId, uid);
    }
    otherGroup = await createGroup(
      conn,
      ownerId: _uidOtherGroupOwner,
      name: 'Outro FA',
    );
    // Ação AVULSA: o criador é a autoridade dela, sem Grupo no meio. É o par
    // do dono do Grupo, e o gatilho trata os dois pelo mesmo predicado.
    looseActionId = await createLooseAction(
      conn,
      creatorId: _uidAuthor,
      name: 'Ação avulsa FA',
    );
  });

  tearDownAll(() async {
    // Por id e por espaço DESTE arquivo, nunca por padrão que outro arquivo
    // possa casar — a suíte roda os arquivos em paralelo contra o mesmo banco.
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where grupo_id = any(@gs::uuid[]) '
        'or acao_id = @a',
      ),
      parameters: {
        'gs': [groupId, otherGroup],
        'a': looseActionId,
      },
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': looseActionId},
    );
    // `participacoes_grupo` sai por cascade do Grupo, e apagá-la antes seria
    // o Dono saindo do próprio Grupo — `checar_dono_nao_sai_sem_transferir`
    // recusa, com razão.
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@us::uuid[])'),
      parameters: {
        'us': [_uidOwner, _uidOtherGroupOwner],
      },
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _uidAdmin},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  setUp(clearChats);

  group('4.1 — fixar é de quem manda no espaço', () {
    test('o dono do Grupo fixa', () async {
      final id = await seed(group: groupId);
      expect(await pinRowsAs(_uidOwner, id), 1);
      final state = await pinnedStateOf(conn, id);
      expect(state.pinned, isTrue);
      expect(state.pinnedBy, _uidOwner, reason: 'fica gravado QUEM fixou');
    });

    test('o criador da Ação avulsa fixa', () async {
      final id = await seed(action: looseActionId);
      expect(await pinRowsAs(_uidAuthor, id), 1);
      expect((await pinnedStateOf(conn, id)).pinned, isTrue);
    });

    test('o Administrador do distrito fixa', () async {
      // Ele MODERA sem LER o chat de Ação — `pode_ver_chat_acao` não tem braço
      // de Administrador. É por isso que o gatilho conta o teto como
      // `security definer`: como `invoker`, a contagem dele seria zero e o teto
      // não valeria para quem mais tem alcance no app.
      final id = await seed(group: groupId);
      expect(await pinRowsAs(_uidAdmin, id), 1);
      expect((await pinnedStateOf(conn, id)).pinnedBy, _uidAdmin);
    });

    test('participante comum não fixa — zero linha, não exceção', () async {
      final id = await seed(group: groupId);
      expect(
        await pinRowsAs(_uidMember, id),
        0,
        reason: 'a policy recusa antes do gatilho, e recusa é ausência',
      );
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('participante comum não fixa nem a própria mensagem', () async {
      // Aqui a policy DEIXA passar — o braço do autor existe para ele poder
      // remover o que escreveu. Quem barra é o gatilho, e por isso este caso é
      // exceção enquanto o de cima é zero linha.
      final id = await seed(group: groupId);
      final error = await pinAs(_uidAuthor, id);
      expect(error, isA<ServerException>());
      expect((error! as ServerException).code, 'PT403');
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('o dono de OUTRO Grupo não fixa', () async {
      final id = await seed(group: groupId);
      expect(await pinRowsAs(_uidOtherGroupOwner, id), 0);
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('fixar em nome de outra pessoa é recusado', () async {
      // Carimbar por cima seria pior do que recusar: quem mandou não ficaria
      // sabendo que foi ignorado. Mesma escolha de 20260817120000 sobre
      // `created_at`.
      final id = await seed(group: groupId);
      final error = await asUser(conn, _uidOwner, () async {
        try {
          await conn.execute(
            Sql.named(
              'update public.mensagens set fixada_em = now(), '
              'fixada_por = @outro where id = @m',
            ),
            parameters: {'m': id, 'outro': _uidAdmin},
          );
          return null;
        } catch (e) {
          return e;
        }
      });
      expect((error! as ServerException).code, 'PT403');
    });
  });

  group('4.2 — o autor sempre desfixa a própria mensagem', () {
    test('autor desfixa mensagem que o dono fixou', () async {
      final id = await seed(group: groupId);
      expect(await pinRowsAs(_uidOwner, id), 1);

      final rows = await asUser(
        conn,
        _uidAuthor,
        () => unpinMessage(conn, messageId: id),
      );
      expect(rows, 1, reason: 'sem este caminho o prazo dele dependeria de outra pessoa');
      final state = await pinnedStateOf(conn, id);
      expect(state.pinned, isFalse);
      expect(state.pinnedBy, isNull, reason: 'as duas colunas andam juntas');
    });

    test('autor sem autoridade não fixa de volta', () async {
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);
      await asUser(conn, _uidAuthor, () => unpinMessage(conn, messageId: id));

      final error = await pinAs(_uidAuthor, id);
      expect((error! as ServerException).code, 'PT403');
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('LIMITE CONHECIDO: o autor que saiu do Grupo não desfixa', () async {
      // ISTO NÃO É O COMPORTAMENTO QUE A SPEC PEDE — é o que o app faz hoje, e
      // o teste existe para o limite não mudar em silêncio nos dois sentidos.
      // A requirement diz "o autor desfixe mensagem que ele escreveu, mesmo sem
      // ter autoridade no espaço"; medido em 2026-08-17, sair do Grupo tira
      // dele o desfixe. Aberto em `PENDENCIAS.md` 2.28, e DECLARADO na Política
      // de Privacidade 1.7 em vez de prometido.
      //
      // A causa não é a policy de `update`, que acerta: no Postgres um `UPDATE`
      // só alcança linha que a policy de `SELECT` deixa a sessão ler, e
      // `pode_ver_chat_grupo` passou a devolver `false`. Por isso a asserção
      // abaixo confere as DUAS coisas — a permissão diz sim, e a linha some.
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);

      await conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo where grupo_id = @g '
          'and usuario_id = @u',
        ),
        parameters: {'g': groupId, 'u': _uidAuthor},
      );
      addTearDown(() => joinGroup(conn, groupId, _uidAuthor));

      final permitted = await asUser(conn, _uidAuthor, () async {
        final r = await conn.execute(
          Sql.named('select public.pode_moderar_mensagem(@a, @g, null)'),
          parameters: {'a': _uidAuthor, 'g': groupId},
        );
        return r.first[0]! as bool;
      });
      expect(permitted, isTrue, reason: 'a permissão continua dizendo sim');

      final rows = await asUser(
        conn,
        _uidAuthor,
        () => unpinMessage(conn, messageId: id),
      );
      expect(
        rows,
        0,
        reason: 'se isto virar 1, o limite fechou e PENDENCIAS 2.28 sai',
      );
      expect((await pinnedStateOf(conn, id)).pinned, isTrue);
    });

    test('participante comum não desfixa a mensagem de outro', () async {
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);

      final rows = await asUser(
        conn,
        _uidMember,
        () => unpinMessage(conn, messageId: id),
      );
      expect(rows, 0);
      expect((await pinnedStateOf(conn, id)).pinned, isTrue);
    });
  });

  group('4.3 — o teto por chat', () {
    test('três passam, a quarta é recusada, desfixar libera', () async {
      final ids = [
        for (var i = 0; i < 4; i++) await seed(group: groupId),
      ];

      for (final id in ids.take(3)) {
        expect(await pinRowsAs(_uidOwner, id), 1);
      }
      expect(await pinnedCountIn(conn, groupId: groupId), 3);

      final error = await pinAs(_uidOwner, ids[3]);
      expect(error, isA<ServerException>());
      final refused = error! as ServerException;
      expect(refused.code, 'PT409');
      expect(
        refused.hint,
        '3',
        reason: 'a tela diz "desfixe uma das 3" sem interpretar texto de erro',
      );
      expect(await pinnedCountIn(conn, groupId: groupId), 3);

      await asUser(conn, _uidOwner, () => unpinMessage(conn, messageId: ids[0]));
      expect(await pinRowsAs(_uidOwner, ids[3]), 1);
      expect(await pinnedCountIn(conn, groupId: groupId), 3);
    });

    test('o teto é POR chat — o outro Grupo não é afetado', () async {
      for (var i = 0; i < 3; i++) {
        expect(await pinRowsAs(_uidOwner, await seed(group: groupId)), 1);
      }
      final elsewhere = await seedMessage(
        conn,
        authorId: _uidOtherGroupOwner,
        groupId: otherGroup,
        text: 'no outro Grupo',
      );
      expect(await pinRowsAs(_uidOtherGroupOwner, elsewhere), 1);
    });

    test('o teto vale no chat de AÇÃO, não só no de Grupo', () async {
      // O gatilho trava `public.grupos` OU `public.acoes` conforme o espaço, e
      // até a convergência 1 o segundo braço não rodava na suíte inteira —
      // funcionava sem prova. Ação AVULSA, cujo criador é a autoridade dela.
      final ids = [
        for (var i = 0; i < 4; i++) await seed(action: looseActionId),
      ];
      for (final id in ids.take(3)) {
        expect(await pinRowsAs(_uidAuthor, id), 1);
      }
      expect(await pinnedCountIn(conn, actionId: looseActionId), 3);

      final error = await pinAs(_uidAuthor, ids[3]);
      expect((error! as ServerException).code, 'PT409');
      expect(await pinnedCountIn(conn, actionId: looseActionId), 3);
    });

    test('fixar mensagem já fixada não reescreve quem fixou', () async {
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);
      final first = await pinnedStateOf(conn, id);

      // O Administrador também tem autoridade, e um segundo toque dele não pode
      // levar o crédito de uma decisão que não foi dele. Mesma escolha que
      // `removida_por` já fazia.
      expect(await pinRowsAs(_uidAdmin, id), 1);
      final second = await pinnedStateOf(conn, id);
      expect(second.pinnedBy, first.pinnedBy);
      expect(second.pinnedBy, _uidOwner);
    });

    test('refixar não consome vaga', () async {
      final ids = [
        for (var i = 0; i < 3; i++) await seed(group: groupId),
      ];
      for (final id in ids) {
        await pinRowsAs(_uidOwner, id);
      }
      // A terceira de novo: se o gatilho contasse a própria linha como nova,
      // esta chamada bateria no teto.
      expect(await pinRowsAs(_uidOwner, ids[2]), 1);
      expect(await pinnedCountIn(conn, groupId: groupId), 3);
    });
  });

  test('4.4 — duas fixações simultâneas com uma vaga fixam exatamente uma',
      () async {
    // SEM A TRAVA ESTE É O CASO QUE PASSA AS DUAS: as duas transações contam
    // 2 fixadas, as duas concluem que cabe mais uma, e as duas gravam — teto
    // de 3 com 4 fixadas no fim. O `for update` na linha do GRUPO põe a
    // segunda na fila até a primeira comitar.
    //
    // A trava é no espaço e não no Perfil, ao contrário de
    // `mensagens_ritmo_de_envio`: aqui o recurso disputado é do chat.
    for (var i = 0; i < 2; i++) {
      await pinRowsAs(_uidOwner, await seed(group: groupId));
    }
    final first = await seed(group: groupId);
    final second = await seed(group: groupId);

    final other = await openTestConnection();
    try {
      Future<Object?> pinOn(Connection c, String messageId) async {
        try {
          await c.execute('set role authenticated');
          await c.execute(
            "set request.jwt.claims to "
            "'{\"sub\":\"$_uidOwner\",\"role\":\"authenticated\"}'",
          );
          await c.execute('begin');
          await pinMessage(c, uid: _uidOwner, messageId: messageId);
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

      final results = await Future.wait([
        pinOn(conn, first),
        pinOn(other, second),
      ]);

      expect(
        results.where((r) => r == null).length,
        1,
        reason: 'exatamente uma passa',
      );
      expect(results.whereType<ServerException>().single.code, 'PT409');
      expect(await pinnedCountIn(conn, groupId: groupId), 3);
    } finally {
      await other.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('4.10 — fixar não abre porta que a leitura não abria', () {
    test('quem não participa recebe zero fixadas', () async {
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);

      final visible = await asUser(
        conn,
        _uidOutsider,
        () => visibleMessageCount(conn, groupId: groupId),
      );
      expect(visible, 0);
    });

    test('menor de 18 participante recebe zero fixadas', () async {
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);

      // Ele PARTICIPA do Grupo — o corte é de idade, e vale para a mensagem
      // fixada como vale para qualquer outra. Fixar muda a posição, não quem
      // alcança.
      final visible = await asUser(
        conn,
        _uidMinor,
        () => visibleMessageCount(conn, groupId: groupId),
      );
      expect(visible, 0);
    });
  });

  group('4.11 — o que o gatilho continua recusando', () {
    Future<Object?> updateAs(String uid, String sql, Map<String, Object?> p) =>
        asUser(conn, uid, () async {
          try {
            await conn.execute(Sql.named(sql), parameters: p);
            return null;
          } catch (e) {
            return e;
          }
        });

    test('coluna imutável continua imutável', () async {
      final id = await seed(group: groupId);
      for (final column in ['autor_id', 'grupo_id', 'created_at']) {
        final value = switch (column) {
          'created_at' => 'now()',
          'grupo_id' => "'$otherGroup'::uuid",
          _ => "'$_uidOwner'::uuid",
        };
        final error = await updateAs(
          _uidOwner,
          'update public.mensagens set $column = $value where id = @m',
          {'m': id},
        );
        expect(
          error,
          isA<ServerException>(),
          reason: '$column deixou de ser imutável',
        );
        expect(
          (error! as ServerException).message,
          contains('mensagem enviada não se edita'),
        );
      }
    });

    test('reescrever o texto continua recusado', () async {
      final id = await seed(group: groupId);
      final error = await updateAs(
        _uidOwner,
        "update public.mensagens set texto = 'outra coisa' where id = @m",
        {'m': id},
      );
      expect(
        (error! as ServerException).message,
        contains('o único update permitido em mensagem é a remoção'),
      );
    });

    test('marcar removida sem esvaziar o texto é recusado', () async {
      // Esta recusa é NOVA. Antes desta change ela vinha de graça, porque todo
      // `update` tinha que esvaziar o texto. Agora que fixar não toca em
      // `texto`, a quarta combinação — texto preenchido COM `removida_em` —
      // precisa ser barrada em voz alta: `message.dart` deriva as três lápides
      // de `texto` + `removida_em` contando que ela não existe.
      final id = await seed(group: groupId);
      final error = await updateAs(
        _uidOwner,
        'update public.mensagens set removida_em = now(), removida_por = @u '
        'where id = @m',
        {'m': id, 'u': _uidOwner},
      );
      expect(
        (error! as ServerException).message,
        contains('remoção sem esvaziar o texto não é remoção'),
      );
    });

    test('fixar sem dizer quem fixou para no gatilho, não na constraint',
        () async {
      // A ordem importa para quem lê o erro: o gatilho responde ANTES, e a
      // frase dele diz o que fazer. A constraint é a rede embaixo.
      final id = await seed(group: groupId);
      final error = await updateAs(
        _uidOwner,
        'update public.mensagens set fixada_em = now() where id = @m',
        {'m': id},
      );
      final refused = error! as ServerException;
      expect(refused.code, 'PT403');
      expect(
        refused.message,
        contains('a fixação se registra em nome de quem fixa'),
      );
    });

    test('fixar lápide é RECUSADO, e não aceito sobre nada', () async {
      // Medido na convergência 1: antes deste caso, o `update` devolvia
      // `UPDATE 1` e o estado final era `fixada_em` nulo — o gatilho zerava a
      // fixação e ninguém ficava sabendo. `ChatRepository.pinMessage` confere
      // `affected.isEmpty`, via uma linha, e reportava que tinha fixado.
      //
      // A tela não oferece "Fixar" em lápide, mas quem decide neste projeto é
      // o banco. O desfixe AUTOMÁTICO — a mensagem que vira lápide agora —
      // continua mudo de propósito: lá o gatilho age por conta própria, e o
      // caso de baixo prova que ele continua agindo.
      final id = await seed(group: groupId);
      await asUser(conn, _uidOwner, () async {
        await conn.execute(
          Sql.named(
            'update public.mensagens set texto = null, removida_em = now(), '
            'removida_por = @u where id = @m',
          ),
          parameters: {'m': id, 'u': _uidOwner},
        );
      });

      final error = await pinAs(_uidOwner, id);
      // `PT403` e não `PT409`: o cliente lê a causa do código, e `PT409` faria
      // a tela dizer "desfixe uma das 3" sobre uma mensagem sem texto —
      // recusa certa com explicação falsa.
      expect((error! as ServerException).code, 'PT403');
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('remover mensagem FIXADA continua desfixando em silêncio', () async {
      // O contraste do caso acima. Quem remove não pediu para desfixar, e não
      // pode levar recusa por um efeito que não escolheu.
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);

      final rows = await asUser(conn, _uidOwner, () async {
        final r = await conn.execute(
          Sql.named(
            'update public.mensagens set texto = null, removida_em = now(), '
            'removida_por = @u where id = @m',
          ),
          parameters: {'m': id, 'u': _uidOwner},
        );
        return r.affectedRows;
      });
      expect(rows, 1);
      expect((await pinnedStateOf(conn, id)).pinned, isFalse);
    });

    test('fixar com data forjada é recusado — passada e futura', () async {
      // Achado na convergência 2, medido: `fixada_por` era conferido contra
      // `auth.uid()` e `fixada_em` não era conferido contra nada, então
      // `'2020-01-01'` e `'2099-12-31'` passavam os dois. A faixa ordena por
      // `fixada_em desc` — data futura prende a mensagem no alto para sempre —
      // e a Política 1.7 declara que o app guarda "quem fixou e quando".
      for (final forged in ['2020-01-01T00:00:00Z', '2099-12-31T00:00:00Z']) {
        final id = await seed(group: groupId);
        final error = await asUser(conn, _uidOwner, () async {
          try {
            await conn.execute(
              Sql.named(
                'update public.mensagens set fixada_em = @t::timestamptz, '
                'fixada_por = @u where id = @m',
              ),
              parameters: {'m': id, 'u': _uidOwner, 't': forged},
            );
            return null;
          } catch (e) {
            return e;
          }
        });
        expect(
          (error! as ServerException).code,
          'PT403',
          reason: '$forged passou',
        );
        expect((await pinnedStateOf(conn, id)).pinned, isFalse);
      }
    });

    test('a tolerância de relógio deixa passar desencontro comum', () async {
      // O contraste. Sem esta folga, um aparelho com o relógio um minuto
      // atrasado — que é comum — não conseguiria fixar nada, e a recusa seria
      // sobre um problema que a pessoa não tem como ver nem corrigir.
      final id = await seed(group: groupId);
      final rows = await asUser(conn, _uidOwner, () async {
        final r = await conn.execute(
          Sql.named(
            "update public.mensagens set fixada_em = now() - interval "
            "'1 minute', fixada_por = @u where id = @m",
          ),
          parameters: {'m': id, 'u': _uidOwner},
        );
        return r.affectedRows;
      });
      expect(rows, 1);
      expect((await pinnedStateOf(conn, id)).pinned, isTrue);
    });

    test('desfixar pela metade é recusado pela constraint', () async {
      // Aqui o gatilho deixa passar — quem desfixa tem autoridade — e quem
      // barra é `mensagens_fixada_completa`. As duas colunas andam juntas:
      // `fixada_por` sem `fixada_em` é uma fixação que não existe.
      final id = await seed(group: groupId);
      await pinRowsAs(_uidOwner, id);
      final error = await updateAs(
        _uidOwner,
        'update public.mensagens set fixada_em = null where id = @m',
        {'m': id},
      );
      expect(
        (error! as ServerException).message,
        contains('mensagens_fixada_completa'),
      );
    });
  });
}

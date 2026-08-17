import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `filtro-e-intervalo-de-mensagem`, tarefas 4.1 a 4.5 — o filtro na
/// ESCRITA.
///
/// A recusa acontece na escrita e nunca na exibição, e a diferença não é de
/// arquitetura: o canal de tempo real entrega a linha assim que ela existe.
/// Mensagem gravada e escondida depois já foi lida por quem estava com o chat
/// aberto — que é justamente quem se quis proteger.
///
/// Tudo aqui escreve como `authenticated`, com `request.jwt.claims`, e não como
/// superusuário. Não é preciosismo: `palavra_bloqueada_em` é `security definer`
/// PARA sobreviver a esse papel, e um teste que rodasse como `postgres`
/// continuaria verde se ela virasse `invoker` — enxergando a lista vazia e
/// aceitando tudo.

const _uidAuthor = 'd5000000-0000-0000-0000-000000000001';
const _uidOther = 'd5000000-0000-0000-0000-000000000002';
const _uidAdmin = 'd5000000-0000-0000-0000-000000000003';
const _allUids = [_uidAuthor, _uidOther, _uidAdmin];

/// Só na lista de CONVERSA.
const _onlyChat = 'zoroxo';

/// Segunda palavra de conversa, para o caso de duas na mesma mensagem.
const _onlyChatToo = 'zaraxa';

/// Já está na lista de NOMES (`palavras_bloqueadas`, feature 001) e NÃO entra
/// na de conversa. É o que prova que as duas listas são independentes.
const _onlyName = 'idiota';

void main() {
  late Connection conn;
  late String groupId;

  Future<Object?> attempt(String uid, Future<void> Function() action) async {
    try {
      await asUser(conn, uid, action);
      return null;
    } catch (e) {
      return e;
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await lockBlockedWordList(conn);
    await conn.execute(
      Sql.named(
        'insert into public.palavras_bloqueadas_mensagem (palavra) '
        'values (@a), (@b) on conflict do nothing',
      ),
      parameters: {'a': _onlyChat, 'b': _onlyChatToo},
    );

    for (final uid in _allUids) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: 30,
      );
    }
    await createTestDistrictAdmin(conn, _uidAdmin);
    groupId = await createGroup(conn, ownerId: _uidAuthor, name: 'Grupo AF');
    await joinGroup(conn, groupId, _uidOther);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.denuncias_mensagem where mensagem_id in '
        '(select id from public.mensagens where grupo_id = @g)',
      ),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _uidAdmin},
    );
    await conn.execute(
      Sql.named(
        'delete from public.palavras_bloqueadas_mensagem '
        'where palavra = any(@ps::text[])',
      ),
      parameters: {
        'ps': [_onlyChat, _onlyChatToo],
      },
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('4.1 mensagem com palavra da lista é recusada, e a recusa diz qual', () async {
    final error = await attempt(
      _uidAuthor,
      () => writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'nao venha com $_onlyChat pra cima de mim',
      ),
    );

    expect(error, isA<ServerException>());
    final e = error! as ServerException;
    // O `hint` é o canal de máquina: a tela lê DELE, não do texto da mensagem.
    expect(e.hint, _onlyChat);
    expect(e.code, 'PT422');

    // E nada foi gravado. Sem esta linha, o caso passaria com um gatilho
    // `after insert` que grava e depois reclama — e o canal já teria entregue.
    final rows = await conn.execute(
      Sql.named('select count(*) from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    expect(rows.first[0], 0);
  });

  test('4.1 mensagem limpa é aceita', () async {
    final id = await asUser(
      conn,
      _uidAuthor,
      () => writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'quem leva o som?',
      ),
    );
    expect(id, isNotEmpty);
    await conn.execute(
      Sql.named('delete from public.mensagens where id = @m'),
      parameters: {'m': id},
    );
  });

  test('4.1 o filtro roda sob authenticated, que não lê a lista', () async {
    // A metade que faltava do cenário "filtro rodando sob papel sem acesso à
    // lista" (`filtro_palavra_funcao_test.dart` prova a outra). A sessão aqui
    // não consegue nem ler a tabela nem chamar a função — e a recusa acontece
    // assim mesmo, porque quem consulta a lista é o gatilho `security definer`.
    //
    // Como `invoker`, a leitura devolveria ZERO LINHAS em vez de erro (RLS sem
    // policy não recusa, some), e este insert PASSARIA.
    await conn.execute('set role authenticated');
    Object? directRead;
    try {
      await conn.execute(
        "set request.jwt.claims to "
        "'{\"sub\":\"$_uidAuthor\",\"role\":\"authenticated\"}'",
      );
      try {
        await conn.execute('select 1 from public.palavras_bloqueadas_mensagem');
      } catch (e) {
        directRead = e;
      }
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
    expect(directRead, isA<ServerException>());

    final error = await attempt(
      _uidAuthor,
      () => writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'olha o $_onlyChat',
      ),
    );
    expect((error! as ServerException).hint, _onlyChat);
  });

  test('4.1 o filtro vale no chat de AÇÃO também', () async {
    // CONVERGENCE 1. Todo o resto deste arquivo usa Grupo. O gatilho é
    // indiferente ao espaço — ele lê `new.texto` e mais nada —, mas o RITMO tem
    // a mesma cara e foi medido nos dois; deixar o filtro medido em um só é
    // confiar na leitura onde dava para medir.
    final actionId = await createLooseAction(
      conn,
      creatorId: _uidAuthor,
      name: 'Ação AF do filtro',
    );

    try {
      final error = await attempt(
        _uidAuthor,
        () => writeMessage(
          conn,
          authorId: _uidAuthor,
          actionId: actionId,
          text: 'combinado, seu $_onlyChat',
        ),
      );
      expect((error! as ServerException).code, 'PT422');
      expect((error as ServerException).hint, _onlyChat);

      final rows = await conn.execute(
        Sql.named('select count(*) from public.mensagens where acao_id = @a'),
        parameters: {'a': actionId},
      );
      expect(rows.first[0], 0);

      // E o contraste: sem palavra da lista, a mesma Ação aceita.
      final id = await asUser(
        conn,
        _uidAuthor,
        () => writeMessage(
          conn,
          authorId: _uidAuthor,
          actionId: actionId,
          text: 'quem leva o som?',
        ),
      );
      expect(id, isNotEmpty);
    } finally {
      await conn.execute(
        Sql.named('delete from public.mensagens where acao_id = @a'),
        parameters: {'a': actionId},
      );
      await conn.execute("set app.bypass_acoes_protecao to 'true'");
      await conn.execute(
        Sql.named('delete from public.acoes where id = @a'),
        parameters: {'a': actionId},
      );
      await conn.execute('reset app.bypass_acoes_protecao');
    }
  });

  test('4.2 duas palavras da lista: recusa, e a devolvida é uma das duas', () async {
    final error = await attempt(
      _uidAuthor,
      () => writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: '$_onlyChat e $_onlyChatToo no mesmo recado',
      ),
    );

    final e = error! as ServerException;
    expect(e.hint, anyOf(_onlyChat, _onlyChatToo));
    // E não a lista inteira: só sai palavra que já estava no texto enviado.
    expect(e.hint, isNot(contains(' ')));

    final rows = await conn.execute(
      Sql.named('select count(*) from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    expect(rows.first[0], 0);
  });

  test('4.3 as duas listas são independentes — nos DOIS sentidos', () async {
    // Palavra da lista de NOMES, ausente da de conversa: recusada em `perfis`,
    // aceita em `mensagens`. O padrão aceitável num nome de cadastro é mais
    // estrito que numa conversa entre adultos.
    final nameError = await attempt(_uidOther, () async {
      await conn.execute(
        Sql.named('update public.perfis set nome = @n where id = @u'),
        parameters: {'n': 'Fulano $_onlyName Silva', 'u': _uidOther},
      );
    });
    expect(nameError, isA<ServerException>());

    final id = await asUser(
      conn,
      _uidAuthor,
      () => writeMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'nao seja $_onlyName',
      ),
    );
    expect(id, isNotEmpty, reason: 'a lista de nomes não fala pela conversa');
    await conn.execute(
      Sql.named('delete from public.mensagens where id = @m'),
      parameters: {'m': id},
    );

    // E o inverso: palavra da lista de CONVERSA passa num nome de Perfil.
    await asUser(conn, _uidOther, () async {
      await conn.execute(
        Sql.named('update public.perfis set nome = @n where id = @u'),
        parameters: {'n': 'Fulano $_onlyChat Silva', 'u': _uidOther},
      );
    });
    final nome = await conn.execute(
      Sql.named('select nome from public.perfis where id = @u'),
      parameters: {'u': _uidOther},
    );
    expect(nome.single.first, 'Fulano $_onlyChat Silva');
  });

  test('4.4 a lista não chega a quem usa o app, nem ao Administrador', () async {
    // A spec pede "zero linhas". O que o banco faz é MAIS FORTE: sem `grant
    // select`, a leitura é recusada — nenhuma palavra sai, e a tentativa fica
    // registrada como erro em vez de passar por lista vazia. É a mesma postura
    // de `palavras_bloqueadas` desde 20260806090000, e a RLS sem policy fica
    // por trás como segunda barreira caso alguém conceda o grant algum dia.
    for (final uid in [_uidOther, _uidAdmin]) {
      final error = await attempt(uid, () async {
        await conn.execute(
          'select palavra from public.palavras_bloqueadas_mensagem',
        );
      });
      expect(
        error,
        isA<ServerException>(),
        reason:
            'nem Administrador do distrito lê a lista — ela se administra fora '
            'do app, como a de nomes (uid $uid)',
      );
    }
  });

  test('4.5 o motivo também não pode ser REESCRITO com palavra da lista', () async {
    // CONVERGENCE 3. Medido em 2026-08-17, antes do conserto: o dono do Grupo
    // pegava uma denúncia com motivo limpo e reescrevia o `motivo` para uma
    // palavra da lista, e o banco ACEITAVA — o gatilho era `before insert` e
    // mais nada.
    //
    // O contraste que tornou o defeito nítido está logo abaixo: a mesma
    // tentativa em `mensagens.texto` é recusada por `mensagens_so_remove`.
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem a ser denunciada',
    );
    await asUser(conn, _uidOther, () async {
      await conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem (mensagem_id, motivo, '
          'denunciante_id) values (@m, @mo, @d)',
        ),
        parameters: {
          'm': messageId,
          'mo': 'esta mensagem me incomodou',
          'd': _uidOther,
        },
      );
    });
    // O id sai daqui e NÃO de um `returning`: `returning` traz a policy de
    // `select` junto, e `denuncias_mensagem_select_autoridade` deixa o
    // DENUNCIANTE de fora de propósito — quem denunciou não vê a própria
    // denúncia. Com `returning`, o insert legítimo era recusado por 42501.
    final reportId =
        (await conn.execute(
              Sql.named(
                'select id from public.denuncias_mensagem where mensagem_id = @m',
              ),
              parameters: {'m': messageId},
            ))
            .single
            .toColumnMap()['id']!
        as String;

    try {
      // O dono do Grupo é quem modera aqui, e é ele quem tem `update`.
      final error = await attempt(_uidAuthor, () async {
        await conn.execute(
          Sql.named(
            'update public.denuncias_mensagem set motivo = @mo where id = @d',
          ),
          parameters: {'mo': 'seu $_onlyChat', 'd': reportId},
        );
      });
      expect((error! as ServerException).code, 'PT422');
      expect((error as ServerException).hint, _onlyChat);

      final kept = await conn.execute(
        Sql.named('select motivo from public.denuncias_mensagem where id = @d'),
        parameters: {'d': reportId},
      );
      expect(kept.single.first, 'esta mensagem me incomodou');

      // A ARMADILHA, e é por ela que o gatilho de update tem `when`: dar
      // desfecho toca `estado` e `resolvida_em`, NÃO o motivo. Sem a guarda,
      // uma denúncia gravada antes de a palavra entrar na lista viraria
      // impossível de resolver — o moderador levaria PT422 sobre um texto que
      // não escreveu e não pode editar.
      // A montagem reproduz a HISTÓRIA REAL: o motivo foi escrito antes de a
      // palavra entrar na lista. Tirar a palavra, escrever, e recolocá-la é o
      // único jeito honesto de fabricar isso — o gatilho vale para superusuário
      // também, então não há atalho, e não deveria haver.
      await conn.execute(
        Sql.named(
          'delete from public.palavras_bloqueadas_mensagem where palavra = @p',
        ),
        parameters: {'p': _onlyChat},
      );
      await conn.execute(
        Sql.named(
          'update public.denuncias_mensagem set motivo = @mo where id = @d',
        ),
        parameters: {'mo': 'motivo antigo com $_onlyChat dentro', 'd': reportId},
      );
      await conn.execute(
        Sql.named(
          'insert into public.palavras_bloqueadas_mensagem (palavra) '
          'values (@p)',
        ),
        parameters: {'p': _onlyChat},
      );

      expect(
        await attempt(_uidAuthor, () async {
          await conn.execute(
            Sql.named(
              "update public.denuncias_mensagem set estado = 'improcedente', "
              'resolvida_em = now() where id = @d',
            ),
            parameters: {'d': reportId},
          );
        }),
        isNull,
        reason:
            'denúncia antiga com palavra da lista continua RESOLVÍVEL — o '
            'gatilho de update só olha quando o motivo muda',
      );
    } finally {
      await conn.execute(
        Sql.named('delete from public.denuncias_mensagem where mensagem_id = @m'),
        parameters: {'m': messageId},
      );
      await conn.execute(
        Sql.named('delete from public.mensagens where id = @m'),
        parameters: {'m': messageId},
      );
    }
  });

  test('4.5 denúncia com palavra da lista no motivo é recusada', () async {
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem qualquer',
    );

    final error = await attempt(_uidOther, () async {
      await conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
        ),
        parameters: {
          'm': messageId,
          'mo': 'esse cara e um $_onlyChat',
          'd': _uidOther,
        },
      );
    });

    final e = error! as ServerException;
    expect(e.code, 'PT422');
    expect(e.hint, _onlyChat);

    final rows = await conn.execute(
      Sql.named(
        'select count(*) from public.denuncias_mensagem where mensagem_id = @m',
      ),
      parameters: {'m': messageId},
    );
    expect(rows.first[0], 0, reason: 'sem isto o campo de denúncia vira a via '
        'aberta que o chat deixou de ser — e ele é lido por quem modera');

    // Motivo limpo continua passando: o filtro não fechou a denúncia.
    await asUser(conn, _uidOther, () async {
      await conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
        ),
        parameters: {
          'm': messageId,
          'mo': 'esta mensagem me incomodou',
          'd': _uidOther,
        },
      );
    });

    await conn.execute(
      Sql.named('delete from public.denuncias_mensagem where mensagem_id = @m'),
      parameters: {'m': messageId},
    );
    await conn.execute(
      Sql.named('delete from public.mensagens where id = @m'),
      parameters: {'m': messageId},
    );
  });
}

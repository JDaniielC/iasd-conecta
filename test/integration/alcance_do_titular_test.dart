import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `alcance-do-titular-sobre-texto-proprio` — o autor alcança a
/// própria mensagem fixada mesmo de fora da conversa.
///
/// `mensagem-fixada` já ACEITA o autor no braço de desfixe
/// (`pode_moderar_mensagem`, com `coalesce`). O que faltava não era
/// permissão — era ALCANCE: um `UPDATE ... WHERE` só enxerga linha que a
/// policy de `SELECT` deixa a sessão ler, e `pode_ver_chat_grupo` /
/// `pode_ver_chat_acao` passam a `false` para quem sai do Grupo, desiste da
/// Ação ou perde o corte de idade. Medido em `PENDENCIAS.md` 2.28.
///
/// Por isso os testes daqui **tiram** a pessoa do espaço (sai do Grupo,
/// desiste da Ação, corrige a idade) e só DEPOIS chamam a função — sem isso
/// o teste provaria o caminho de dentro da conversa, que já funcionava.

const _uidOwner = '2a000000-0000-0000-0000-000000000001';
const _uidAuthor = '2a000000-0000-0000-0000-000000000002';
const _uidOther = '2a000000-0000-0000-0000-000000000003';
const _uidCreator = '2a000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidAuthor, _uidOther, _uidCreator];

void main() {
  late Connection conn;

  Future<int> desfixarMinhaMensagem(String messageId) async {
    final r = await conn.execute(
      Sql.named('select public.desfixar_minha_mensagem(@m)'),
      parameters: {'m': messageId},
    );
    return r.first[0]! as int;
  }

  Future<List<Map<String, dynamic>>> minhasMensagensFixadas() async {
    final r = await conn.execute('select * from public.minhas_mensagens_fixadas()');
    return [for (final row in r) row.toColumnMap()];
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfileWithAge(conn, uid, name: 'Titular $uid', age: 30);
    }
  });

  tearDownAll(() async {
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  tearDown(() async {
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where autor_id = any(@ids::uuid[])',
      ),
      parameters: {'ids': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = any(@ids::uuid[])'),
      parameters: {'ids': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@ids::uuid[])'),
      parameters: {'ids': _allUids},
    );
  });

  test('autor que saiu do Grupo desfixa pela função (PENDENCIAS.md 2.28)',
      () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidAuthor);
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'o ponto de encontro mudou',
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageId),
    );
    expect((await pinnedStateOf(conn, messageId)).pinned, isTrue);

    // Sai do Grupo — a policy de leitura passa a esconder a linha dele.
    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo '
        'where grupo_id = @g and usuario_id = @u',
      ),
      parameters: {'g': groupId, 'u': _uidAuthor},
    );
    expect(
      await asUser(conn, _uidAuthor, () => canSeeGroupChat(conn, groupId)),
      isFalse,
      reason: 'a premissa do achado: ele não lê mais o chat',
    );

    final linhas = await asUser(
      conn,
      _uidAuthor,
      () => desfixarMinhaMensagem(messageId),
    );

    expect(linhas, 1);
    expect((await pinnedStateOf(conn, messageId)).pinned, isFalse);
  });

  test('autor que desistiu da Ação desfixa', () async {
    final actionId = await createLooseAction(conn, creatorId: _uidCreator);
    await conn.execute(
      Sql.named(
        "insert into public.confirmacoes_acao (acao_id, usuario_id, status) "
        "values (@a, @u, 'confirmado')",
      ),
      parameters: {'a': actionId, 'u': _uidAuthor},
    );
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      actionId: actionId,
      text: 'quem leva a caixa de som?',
    );
    await asUser(
      conn,
      _uidCreator,
      () => pinMessage(conn, uid: _uidCreator, messageId: messageId),
    );

    // Desiste — mesmo caso do teste acima, espaço diferente.
    await conn.execute(
      Sql.named(
        'delete from public.confirmacoes_acao '
        'where acao_id = @a and usuario_id = @u',
      ),
      parameters: {'a': actionId, 'u': _uidAuthor},
    );
    expect(
      await asUser(conn, _uidAuthor, () => canSeeActionChat(conn, actionId)),
      isFalse,
    );

    final linhas = await asUser(
      conn,
      _uidAuthor,
      () => desfixarMinhaMensagem(messageId),
    );

    expect(linhas, 1);
    expect((await pinnedStateOf(conn, messageId)).pinned, isFalse);
  });

  test('autor com idade corrigida para 17 desfixa', () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidAuthor);
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'combinado, chego às 8',
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageId),
    );

    // O corte de idade decide o que ela LÊ, não o que ela retira do que
    // escreveu. `apelido` junto: `apelido_obrigatorio_menor` recusa a idade
    // sozinha.
    await conn.execute(
      Sql.named(
        "update public.perfis set idade = 17, apelido = 'Titular' where id = @u",
      ),
      parameters: {'u': _uidAuthor},
    );
    expect(
      await asUser(conn, _uidAuthor, () => canSeeGroupChat(conn, groupId)),
      isFalse,
    );

    final linhas = await asUser(
      conn,
      _uidAuthor,
      () => desfixarMinhaMensagem(messageId),
    );

    expect(linhas, 1);
  });

  test('não autor chamando a função sobre mensagem alheia: zero linhas, e '
      'a mensagem continua fixada — inclui quem tem autoridade no espaço',
      () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidAuthor);
    await joinGroup(conn, groupId, _uidOther);
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'texto do autor',
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageId),
    );

    // Participante comum: nunca teve o caminho.
    expect(
      await asUser(conn, _uidOther, () => desfixarMinhaMensagem(messageId)),
      0,
    );
    // Quem TEM autoridade no espaço: ela tem o caminho de DENTRO da
    // conversa, não este — o predicado é só `autor_id`, sem braço de
    // autoridade.
    expect(
      await asUser(conn, _uidOwner, () => desfixarMinhaMensagem(messageId)),
      0,
    );
    expect((await pinnedStateOf(conn, messageId)).pinned, isTrue);
  });

  test('minhas_mensagens_fixadas de uma pessoa não traz mensagem de outra '
      'na mesma conversa', () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidAuthor);
    await joinGroup(conn, groupId, _uidOther);
    final messageA = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem de quem escreveu A',
    );
    final messageB = await seedMessage(
      conn,
      authorId: _uidOther,
      groupId: groupId,
      text: 'mensagem de quem escreveu B',
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageA),
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageB),
    );

    final deA = await asUser(conn, _uidAuthor, minhasMensagensFixadas);
    expect(deA.map((r) => r['id']), [messageA]);

    final deB = await asUser(conn, _uidOther, minhasMensagensFixadas);
    expect(deB.map((r) => r['id']), [messageB]);
  });

  test('minhas_mensagens_fixadas de quem saiu do Grupo traz a fixada dele '
      'daquele Grupo — o caso que a policy de select esconde', () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidAuthor);
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'o texto que ele quer reaver',
    );
    await asUser(
      conn,
      _uidOwner,
      () => pinMessage(conn, uid: _uidOwner, messageId: messageId),
    );
    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo '
        'where grupo_id = @g and usuario_id = @u',
      ),
      parameters: {'g': groupId, 'u': _uidAuthor},
    );

    final fixadas = await asUser(conn, _uidAuthor, minhasMensagensFixadas);

    expect(fixadas, hasLength(1));
    expect(fixadas.single['id'], messageId);
    expect(fixadas.single['nome_espaco'], isNotNull);
  });

  test('a função de leitura não devolve fixada_por — lista de colunas', () async {
    final r = await conn.execute(
      'select * from public.minhas_mensagens_fixadas() limit 0',
    );
    final colunas = r.schema.columns.map((c) => c.columnName ?? '').toSet();

    expect(colunas, isNot(contains('fixada_por')));
    expect(colunas, containsAll(['id', 'texto', 'fixada_em', 'nome_espaco']));
  });

  test('as duas funções não são alcançáveis sem sessão: anon recebe 42501',
      () async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    final messageId = await seedMessage(
      conn,
      authorId: _uidOwner,
      groupId: groupId,
      text: 'qualquer texto',
    );

    await expectLater(
      asAnon(
        conn,
        () => conn.execute(
          Sql.named('select public.desfixar_minha_mensagem(@m)'),
          parameters: {'m': messageId},
        ),
      ),
      throwsA(isA<ServerException>()),
    );

    await expectLater(
      asAnon(
        conn,
        () => conn.execute('select * from public.minhas_mensagens_fixadas()'),
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('depois de desfixar pela função, o expurgo seguinte apaga a mensagem '
      'vencida — sem carência nova', () async {
    final actionId = await createLooseAction(
      conn,
      creatorId: _uidCreator,
      interval: "interval '-31 days'",
    );
    await conn.execute(
      Sql.named(
        "insert into public.confirmacoes_acao (acao_id, usuario_id, status) "
        "values (@a, @u, 'confirmado')",
      ),
      parameters: {'a': actionId, 'u': _uidAuthor},
    );
    final messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      actionId: actionId,
      text: 'endereço combinado',
    );
    await asUser(
      conn,
      _uidCreator,
      () => pinMessage(conn, uid: _uidCreator, messageId: messageId),
    );

    // Fixada, então o expurgo NÃO apaga ainda, mesmo vencida.
    await conn.execute('select public.expurgar_mensagens_de_acao()');
    expect((await messageStateOf(conn, messageId)).hasText, isTrue);

    final linhas = await asUser(
      conn,
      _uidAuthor,
      () => desfixarMinhaMensagem(messageId),
    );
    expect(linhas, 1);

    await conn.execute('select public.expurgar_mensagens_de_acao()');
    final r = await conn.execute(
      Sql.named('select count(*) from public.mensagens where id = @m'),
      parameters: {'m': messageId},
    );
    expect(r.first[0], 0);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'mudancas_helper.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — os gatilhos de `acoes`.
///
/// O registro diz QUE mudou, não de que para que. O que ele precisa acertar é
/// mais estreito e mais fácil de errar: disparar nas colunas certas, uma vez
/// por coluna, e só na TRANSIÇÃO de cancelamento. Um `update` que toca
/// `detalhes` não é mudança para quem confirmou presença.

const _uidDona = 'd2000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;
  late String groupId, roundId;

  Future<String> novaAcaoDeGrupo(String nome) => createGroupAction(conn,
      creatorId: _uidDona, roundId: roundId, name: nome);

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona D2');
    groupId = await createGroup(conn, ownerId: _uidDona, name: 'Grupo D2');
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidDona);
  });

  tearDownAll(() async {
    await limparMudancasDoGrupo(conn, groupId);
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, _uidDona);
    await conn.close();
  });

  test('mudar só o horário gera exatamente 1 acao_horario_alterado', () async {
    final id = await novaAcaoDeGrupo('D2 horário');
    await conn.execute(
      Sql.named("update public.acoes set data_hora = now() + interval '9 days' where id = @a"),
      parameters: {'a': id},
    );
    final tipos = await tiposDaAcao(conn, id);
    expect(tipos['acao_horario_alterado'], 1);
    expect(tipos.containsKey('acao_local_alterado'), isFalse);
  });

  test('mudar horário e local na mesma operação gera 2 registros, com o mesmo '
      'created_at', () async {
    final id = await novaAcaoDeGrupo('D2 ambos');
    await conn.execute(
      Sql.named(
          "update public.acoes set data_hora = now() + interval '9 days', local = 'Praça' where id = @a"),
      parameters: {'a': id},
    );
    final tipos = await tiposDaAcao(conn, id);
    expect(tipos['acao_horario_alterado'], 1);
    expect(tipos['acao_local_alterado'], 1);

    // Mesma transação, mesmo instante: `now()` é o do início da transação.
    final r = await conn.execute(
      Sql.named(
          "select count(distinct created_at) from public.mudancas where acao_id = @a and tipo like 'acao_%alterado'"),
      parameters: {'a': id},
    );
    expect(r.first[0], 1);
  });

  test('update que toca só detalhes, nome ou limite_vagas gera 0 registros',
      () async {
    final id = await novaAcaoDeGrupo('D2 inerte');
    await limparMudancasDoGrupo(conn, groupId);
    await conn.execute(
      Sql.named(
          "update public.acoes set detalhes = 'x', nome = 'D2 inerte 2', limite_vagas = 9 where id = @a"),
      parameters: {'a': id},
    );
    expect(await tiposDaAcao(conn, id), isEmpty);
  });

  test('cancelar gera 1 acao_cancelada, e um segundo update não repete',
      () async {
    final id = await novaAcaoDeGrupo('D2 cancelada');
    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @a'),
      parameters: {'a': id},
    );
    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @a'),
      parameters: {'a': id},
    );
    final tipos = await tiposDaAcao(conn, id);
    expect(tipos['acao_cancelada'], 1,
        reason: 'só a TRANSIÇÃO de nulo para não nulo é evento');
  });

  test('sessão sem Perfil não derruba a operação — autor sai nulo', () async {
    // REGRESSÃO. `autor_id` referencia `perfis(id)`, e nem todo `auth.uid()`
    // tem Perfil: a sessão existe em `auth.users` desde o login e o Perfil vem
    // depois. Sem resolver o autor para nulo, o gatilho estourava com violação
    // de FK — e como ele não captura exceção, de propósito, derrubava a
    // operação de origem junto. Achado por `account_deletion_test`, não por
    // teste desta change.
    const semPerfil = 'd2000000-0000-0000-0000-0000000000ff';
    await createTestUser(conn, semPerfil);
    final id = await novaAcaoDeGrupo('D2 sem perfil');

    await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$semPerfil\",\"role\":\"authenticated\"}'");
    try {
      await conn.execute(
        Sql.named("update public.acoes set local = 'Outro lugar' where id = @a"),
        parameters: {'a': id},
      );
    } finally {
      await conn.execute('reset request.jwt.claims');
    }

    final r = await conn.execute(
      Sql.named(
          "select autor_id from public.mudancas where acao_id = @a and tipo = 'acao_local_alterado'"),
      parameters: {'a': id},
    );
    expect(r.single.toColumnMap()['autor_id'], isNull,
        reason: 'a tela escreve a frase sem sujeito nesse caso');
    await conn.execute(
      Sql.named('delete from auth.users where id = @u'),
      parameters: {'u': semPerfil},
    );
  });

  test('Ação de Grupo gera acao_criada; Ação avulsa gera 0', () async {
    final deGrupo = await novaAcaoDeGrupo('D2 de grupo');
    expect((await tiposDaAcao(conn, deGrupo))['acao_criada'], 1);

    final avulsa = await createLooseAction(conn, creatorId: _uidDona, name: 'D2 avulsa');
    expect((await tiposDaAcao(conn, avulsa)).containsKey('acao_criada'), isFalse,
        reason: 'Ação avulsa não tem Grupo onde o registro apareceria');
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': avulsa},
    );
  });
}

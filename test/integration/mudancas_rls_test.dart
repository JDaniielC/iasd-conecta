import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'mudancas_helper.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — quem escreve (ninguém) e quem lê.
///
/// A policy de leitura HERDA a visibilidade de `acoes` por subconsulta em vez de
/// copiá-la. Isso importa porque `confirmacao_confirmado` guarda o par nominal
/// `(acao_id, autor_id)` — o mesmo formato de vazamento que a feature 021
/// fechou em `votos`, onde três requisições com a chave pública montavam
/// "Clara Demo votou em Entrega de cestas".
///
/// Com `acao-direcionada-a-grupo` já aplicada, o caso da Ação escondida é
/// montado com uma Ação restrita de verdade, e não simulando revogação.

const _uidDona = 'd4000000-0000-0000-0000-000000000001';
const _uidMembro = 'd4000000-0000-0000-0000-000000000002';
const _uidForasteiro = 'd4000000-0000-0000-0000-000000000003';
const _uidAdmin = 'd4000000-0000-0000-0000-000000000004';
const _allUids = [_uidDona, _uidMembro, _uidForasteiro, _uidAdmin];

/// Visitante: sem cadastro, e por isso FORA de `_allUids` — aquela lista cria
/// Perfil para cada uid, e Visitante é justamente quem não tem.
const _uidVisitor = 'd4000000-0000-0000-0000-0000000000f0';

void main() {
  late Connection conn;
  late String groupId, roundId;
  late String publica, restrita;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestVisitor(conn, _uidVisitor);
    for (final uid in _allUids) {
      await createTestProfile(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
      );
    }
    await createTestDistrictAdmin(conn, _uidAdmin);

    groupId = await createGroup(conn, ownerId: _uidDona, name: 'Grupo D4');
    await joinGroup(conn, groupId, _uidMembro);
    roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidDona,
    );

    publica = await createGroupAction(
      conn,
      creatorId: _uidDona,
      roundId: roundId,
      name: 'D4 pública',
    );
    restrita = await createGroupAction(
      conn,
      creatorId: _uidDona,
      roundId: roundId,
      restricted: true,
      name: 'D4 restrita',
    );
    await conn.execute(
      Sql.named("update public.acoes set local = 'Outro' where id = @a"),
      parameters: {'a': restrita},
    );
  });

  tearDownAll(() async {
    await limparMudancasDoGrupo(conn, groupId);
    await conn.execute(
      Sql.named(
        'update public.rodadas_votacao set vencedora_id = null where grupo_id = @g',
      ),
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
    // Os testes criam Grupos próprios; limpar por dono cobre todos, inclusive
    // os de uma execução que falhou no meio.
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@us::uuid[])'),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidVisitor);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  group('o registro é escrito só pelo banco', () {
    // Três papéis com poder no app — Dono do Grupo, criador da Ação e
    // Administrador do distrito — e as três operações de escrita. Nenhum passa.
    for (final (papel, uid) in [
      ('Dono do Grupo e criador da Ação', _uidDona),
      ('participante', _uidMembro),
      ('Administrador do distrito', _uidAdmin),
    ]) {
      test('$papel não insere, não altera e não apaga', () async {
        for (final sql in [
          "insert into public.mudancas (grupo_id, tipo) values (@g, 'grupo_arquivado')",
          "update public.mudancas set tipo = 'grupo_arquivado' where grupo_id = @g",
          'delete from public.mudancas where grupo_id = @g',
        ]) {
          Object? erro;
          try {
            await asUser(conn, uid, () async {
              await conn.execute(Sql.named(sql), parameters: {'g': groupId});
            });
          } catch (e) {
            erro = e;
          }
          expect(erro, isA<ServerException>(), reason: sql);
        }
      });
    }
  });

  test('Ação pública: Visitante e cadastrado veem as mesmas linhas', () async {
    // Visitante é quem NÃO tem cadastro, e ele tem sessão — até 2026-08-16
    // este teste rodava como `anon`, e media o `grant` em vez da policy.
    final comoVisitante = await asVisitor(
      conn,
      _uidVisitor,
      () => visiveisDaAcao(conn, publica),
    );
    final comoAuth = await asUser(
      conn,
      _uidForasteiro,
      () => visiveisDaAcao(conn, publica),
    );
    expect(comoVisitante, greaterThan(0));
    expect(
      comoVisitante,
      comoAuth,
      reason: 'é o lado que impede a policy de esconder o que não devia',
    );
  });

  test('Ação restrita: os registros dela não vêm para quem é de fora, e a '
      'resposta é vazia e não erro', () async {
    // Existem de verdade — só não são legíveis.
    expect((await tiposDaAcao(conn, restrita))['acao_criada'], 1);
    expect((await tiposDaAcao(conn, restrita))['acao_local_alterado'], 1);
    expect((await tiposDaAcao(conn, restrita))['confirmacao_confirmado'], 1);

    expect(
      await asVisitor(conn, _uidVisitor, () => visiveisDaAcao(conn, restrita)),
      0,
    );
    expect(
      await asUser(conn, _uidForasteiro, () => visiveisDaAcao(conn, restrita)),
      0,
    );
    expect(
      await asUser(conn, _uidMembro, () => visiveisDaAcao(conn, restrita)),
      greaterThan(0),
      reason: 'quem participa continua vendo',
    );
  });

  test('no mesmo Grupo, os eventos sem Ação continuam públicos', () async {
    // A policy filtra por `acao_id`, não por Grupo. Apertar participação sem
    // apertar `participacoes_grupo` seria teatro: o fato segue legível lá.
    final semAcao = await asVisitor(
      conn,
      _uidVisitor,
      () => visiveisDoGrupoSemAcao(conn, groupId),
    );
    expect(semAcao, greaterThan(0));
  });

  test('remoção física do Grupo não deixa órfão nem erro de FK', () async {
    final gid = await createGroup(
      conn,
      ownerId: _uidForasteiro,
      name: 'Grupo D4 efêmero',
    );
    expect((await tiposDoGrupo(conn, gid))['participacao_entrou'], 1);

    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': gid},
    );
    expect(
      await tiposDoGrupo(conn, gid),
      isEmpty,
      reason: 'o registro some junto com o Grupo, por cascata',
    );
  });

  test('depois de excluir a Conta, os registros ficam e o autor aparece '
      'anonimizado', () async {
    final gid = await createGroup(
      conn,
      ownerId: _uidDona,
      name: 'Grupo D4 saida',
    );
    await asUser(conn, _uidMembro, () async {
      await conn.execute(
        Sql.named(
          'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@g, @u)',
        ),
        parameters: {'g': gid, 'u': _uidMembro},
      );
    });

    final r = await conn.execute(
      Sql.named(
        'select count(*) from public.mudancas where grupo_id = @g and autor_id = @u',
      ),
      parameters: {'g': gid, 'u': _uidMembro},
    );
    expect(r.first[0], 1);

    await asUser(conn, _uidMembro, () async {
      await conn.execute('select public.excluir_minha_conta()');
    });

    // O registro de entrada CONTINUA lá. E aparece um segundo, de saída: a
    // exclusão de Conta tira a pessoa dos Grupos, e sair é ele próprio um
    // evento. O registro não é apagado por conta ser excluída — é o ponto do
    // requisito.
    final depois = await conn.execute(
      Sql.named(
        'select tipo from public.mudancas where grupo_id = @g and autor_id = @u order by tipo',
      ),
      parameters: {'g': gid, 'u': _uidMembro},
    );
    expect(
      depois.map((r) => r.toColumnMap()['tipo']),
      containsAll(['participacao_entrou', 'participacao_saiu']),
    );

    final nome = await conn.execute(
      Sql.named('select nome_exibido from public.perfil_publico(@u)'),
      parameters: {'u': _uidMembro},
    );
    expect(nome.single.toColumnMap()['nome_exibido'], 'Membro removido');
  });
}

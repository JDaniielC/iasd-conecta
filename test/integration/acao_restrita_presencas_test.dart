import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — a restrição alcança quem vai.
///
/// Esconder a Ação e deixar a lista de presença aberta seria vazamento por
/// porta lateral: `confirmacoes_acao` devolve o par (acao_id, usuario_id), que
/// entrega de uma vez a existência da Ação e quem estará lá. Foi por um par
/// nominal assim que a feature 021 descobriu o vazamento dos votos.
///
/// A policy nova de `confirmacoes_acao` não repete o `exists` de participação:
/// ela só pergunta se a Ação existe, e a subconsulta roda sob a RLS de `acoes`.
/// Este arquivo é o que prova que a herança funciona — se alguém trocar aquela
/// subconsulta por uma cópia da regra, é aqui que aparece.

const _uidOwner = 'a2000000-0000-0000-0000-000000000001';
const _uidMember = 'a2000000-0000-0000-0000-000000000002';
const _uidOutsider = 'a2000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidMember, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;
  late String restrictedId;
  late String publicId;

  Future<int> confirmationCount(String actionId) async {
    final r = await conn.execute(
      Sql.named(
          'select count(*) from public.confirmacoes_acao where acao_id = @a'),
      parameters: {'a': actionId},
    );
    return r.first[0]! as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A2');
    await createTestProfile(conn, _uidMember, name: 'Participante A2');
    await createTestProfile(conn, _uidOutsider, name: 'De Fora A2');

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo A2');
    await joinGroup(conn, groupId, _uidMember);
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidOwner);

    restrictedId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'Restrita A2',
    );
    publicId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      name: 'Pública A2',
    );
    await makeWinner(conn, roundId, restrictedId);
    // `acoes_criador_vira_confirmado` já pôs quem criou em confirmacoes_acao,
    // então as duas Ações têm presença sem semear nada.
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
          'update public.rodadas_votacao set vencedora_id = null where grupo_id = @g'),
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
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('as confirmações da Ação restrita não vêm para Visitante', () async {
    expect(await asVisitor(conn, () => confirmationCount(restrictedId)), 0);
  });

  test('as confirmações da Ação restrita não vêm para quem é de fora', () async {
    expect(
      await asUser(conn, _uidOutsider, () => confirmationCount(restrictedId)),
      0,
    );
  });

  test('quem participa lê as confirmações da Ação restrita', () async {
    expect(
      await asUser(conn, _uidMember, () => confirmationCount(restrictedId)),
      greaterThan(0),
    );
  });

  test('as confirmações da Ação pública continuam vindo para Visitante',
      () async {
    expect(
      await asVisitor(conn, () => confirmationCount(publicId)),
      greaterThan(0),
    );
  });
}

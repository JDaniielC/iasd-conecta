import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — a Ação restrita some para quem é de fora.
///
/// A promessa é "quem não participa do Grupo não vê". A prova precisa falar com
/// o banco: o REST do Supabase é público e `GET /rest/v1/acoes` com a chave
/// anônima responde direto — foi assim que a feature 021 descobriu que os votos
/// vazavam. Filtro no Dart não é prova de nada aqui.
///
/// O caso menos óbvio é o último: a resposta para quem é de fora tem de ser
/// LISTA VAZIA, nunca erro de permissão. A diferença entre "não existe" e "não
/// posso ver" é contável, e contável é canal lateral —
/// 20260809200000_votos_visibilidade.sql:36-41.

const _uidOwner = 'a1000000-0000-0000-0000-000000000001';
const _uidMember = 'a1000000-0000-0000-0000-000000000002';
const _uidOutsider = 'a1000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidMember, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;
  late String restrictedId;
  late String publicId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A1');
    await createTestProfile(conn, _uidMember, name: 'Participante A1');
    await createTestProfile(conn, _uidOutsider, name: 'De Fora A1');

    groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidMember);
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidOwner);

    restrictedId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'Reunião interna A1',
    );
    publicId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      name: 'Encontro aberto A1',
    );
    // A restrita vence e vira a Ação de Grupo que fica: mesma linha, mesma
    // restrição. É o caso que o proposal descreve (reunião interna de
    // Ministério), não só o da candidata em votação.
    await makeWinner(conn, roundId, restrictedId);
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

  test('Visitante não vê a Ação restrita', () async {
    final n = await asVisitor(conn, () => visibleActionCount(conn, restrictedId));
    expect(n, 0);
  });

  test('autenticado de fora do Grupo não vê a Ação restrita', () async {
    final n =
        await asUser(conn, _uidOutsider, () => visibleActionCount(conn, restrictedId));
    expect(n, 0);
  });

  test('quem participa do Grupo vê a Ação restrita', () async {
    final n =
        await asUser(conn, _uidMember, () => visibleActionCount(conn, restrictedId));
    expect(n, 1);
  });

  test('quem criou vê a própria Ação restrita', () async {
    final n =
        await asUser(conn, _uidOwner, () => visibleActionCount(conn, restrictedId));
    expect(n, 1);
  });

  test('a Ação pública do mesmo Grupo continua visível para todos', () async {
    expect(await asVisitor(conn, () => visibleActionCount(conn, publicId)), 1);
    expect(
      await asUser(conn, _uidOutsider, () => visibleActionCount(conn, publicId)),
      1,
    );
  });

  test('a resposta para quem é de fora é lista vazia, não erro', () async {
    // Se isto virar exceção um dia, o canal lateral voltou: dá para contar o
    // que está escondido só olhando qual resposta chega.
    final rows = await asUser(
      conn,
      _uidOutsider,
      () => conn.execute('select id from public.acoes'),
    );
    expect(rows.map((r) => r.toColumnMap()['id']), isNot(contains(restrictedId)));
    expect(rows.map((r) => r.toColumnMap()['id']), contains(publicId));
  });
}

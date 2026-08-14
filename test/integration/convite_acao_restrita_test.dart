import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao`, task 0.1 — convite para Ação restrita não sai do
/// Grupo dela.
///
/// `acao-direcionada-a-grupo` já está aplicada, então a regra nasceu junto com
/// as funções em vez de virar remendo depois. Um convite para uma Ação que a
/// pessoa não consegue abrir é convite morto — e pior: ele revela que a Ação
/// existe, que é exatamente o que a restrição escondeu.
///
/// Ação de Grupo neste app é candidata de Rodada (`acoes_candidata_checar_regras`
/// recusa `grupo_id` sem `rodada_id`), então a montagem passa pela Rodada.
/// A Ação avulsa de controle prova que a regra não vazou para o caso comum.

const _uidConvidante = 'c9000000-0000-0000-0000-000000000001';
const _uidDoGrupoDaAcao = 'c9000000-0000-0000-0000-000000000002';
const _uidDeOutroGrupo = 'c9000000-0000-0000-0000-000000000003';
const _allUids = [_uidConvidante, _uidDoGrupoDaAcao, _uidDeOutroGrupo];

void main() {
  late Connection conn;
  late String grupoDaAcao, outroGrupo;
  late String roundId;
  late String restrita, avulsa;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidConvidante, name: 'Convidante C9');
    await createTestProfile(conn, _uidDoGrupoDaAcao, name: 'Do Grupo da Acao C9');
    await createTestProfile(conn, _uidDeOutroGrupo, name: 'De Outro Grupo C9');

    grupoDaAcao =
        await createGroup(conn, ownerId: _uidConvidante, name: 'Dono da Acao C9');
    outroGrupo =
        await createGroup(conn, ownerId: _uidConvidante, name: 'Outro C9');
    await joinGroup(conn, grupoDaAcao, _uidDoGrupoDaAcao);
    await joinGroup(conn, outroGrupo, _uidDeOutroGrupo);

    roundId = await createVotingRound(conn,
        groupId: grupoDaAcao, openedBy: _uidConvidante);
    restrita = await createGroupAction(conn,
        creatorId: _uidConvidante,
        roundId: roundId,
        restricted: true,
        name: 'Reunião restrita C9');
    avulsa =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Avulsa C9');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.convites_acao where acao_id in (@r, @a)'),
      parameters: {'r': restrita, 'a': avulsa},
    );
    await conn.execute(
      Sql.named(
          'update public.rodadas_votacao set vencedora_id = null where id = @r'),
      parameters: {'r': roundId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id in (@r, @a)'),
      parameters: {'r': restrita, 'a': avulsa},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where id = @r'),
      parameters: {'r': roundId},
    );
    for (final g in [grupoDaAcao, outroGrupo]) {
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

  test('na Ação avulsa, os dois Grupos aparecem — a regra não vazou para o '
      'caso comum', () async {
    final linhas =
        await asUser(conn, _uidConvidante, () => contatosParaConvite(conn, avulsa));
    expect(linhas.map((l) => l['grupo_nome']).toSet(),
        {'Dono da Acao C9', 'Outro C9'});
  });

  test('na Ação restrita, só a seção do Grupo dono é oferecida', () async {
    final linhas = await asUser(
        conn, _uidConvidante, () => contatosParaConvite(conn, restrita));
    expect(linhas.map((l) => l['grupo_nome']).toSet(), {'Dono da Acao C9'});
    expect(
      linhas.map((l) => l['nome_exibido']),
      isNot(contains('De Outro Grupo C9')),
    );
  });

  test('convidar para a Ação restrita por outro Grupo é recusado', () async {
    await expectLater(
      asUser(
        conn,
        _uidConvidante,
        () => convidarParaAcao(conn,
            actionId: restrita,
            groupId: outroGrupo,
            invitees: [_uidDeOutroGrupo]),
      ),
      throwsA(isA<ServerException>()),
    );
    expect(await convitesGravados(conn, restrita), isEmpty);
  });

  test('convidar para a Ação restrita pelo Grupo dela funciona', () async {
    final r = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: restrita,
          groupId: grupoDaAcao,
          invitees: [_uidDoGrupoDaAcao]),
    );
    expect(r[_uidDoGrupoDaAcao], 'criado');

    final gravados = await convitesGravados(conn, restrita);
    expect(gravados, hasLength(1));
    expect(gravados.single['grupo_id'], grupoDaAcao);
  });
}

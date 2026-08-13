import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — quem edita a Ação é quem restringe.
///
/// A restrição NÃO ganhou regra de escrita própria: quem pode mexer nela é
/// exatamente quem `acoes_update_criador_dono_grupo_ou_admin` já deixa editar a
/// Ação — criador, Dono do Grupo, Administrador do distrito
/// (`20260724092132_district_admin.sql`). O caso do Administrador é o próximo
/// arquivo, `acao_restrita_admin_assimetria_test.dart`, porque ele carrega uma
/// dívida registrada e merece ficar sozinho.
///
/// Uma versão anterior do design desta change afirmava que só o criador podia
/// escrever em `acoes`. Era falso — `acoes_update_criador` foi substituída em
/// 2026-07-24. Este arquivo existe para a afirmação nunca mais ser feita de
/// memória.
///
/// Quem é recusado por RLS de `update` não recebe erro: recebe ZERO linhas
/// afetadas. Erro seria canal lateral, do mesmo jeito que na leitura.

const _uidOwner = 'a4000000-0000-0000-0000-000000000001';
const _uidMember = 'a4000000-0000-0000-0000-000000000002';
const _uidOutsider = 'a4000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidMember, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;

  Future<bool?> restrictionOf(String actionId) async {
    final r = await conn.execute(
      Sql.named('select restrita_ao_grupo from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    return r.single.toColumnMap()['restrita_ao_grupo'] as bool?;
  }

  Future<int> setRestriction(String uid, String actionId, bool value) async {
    return asUser(conn, uid, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.acoes set restrita_ao_grupo = @v where id = @a'),
        parameters: {'a': actionId, 'v': value},
      );
      return r.affectedRows;
    });
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A4');
    await createTestProfile(conn, _uidMember, name: 'Participante A4');
    await createTestProfile(conn, _uidOutsider, name: 'De Fora A4');

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo A4');
    await joinGroup(conn, groupId, _uidMember);
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidOwner);
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

  test('quem criou muda a restrição nos dois sentidos', () async {
    final id = await createGroupAction(
        conn, creatorId: _uidOwner, roundId: roundId, name: 'A4 ida e volta');

    expect(await setRestriction(_uidOwner, id, true), 1);
    expect(await restrictionOf(id), isTrue);

    expect(await setRestriction(_uidOwner, id, false), 1);
    expect(await restrictionOf(id), isFalse);
  });

  test('o Dono do Grupo restringe Ação criada por um participante', () async {
    final id = await createGroupAction(
        conn, creatorId: _uidMember, roundId: roundId, name: 'A4 do participante');

    expect(await setRestriction(_uidOwner, id, true), 1);
    expect(await restrictionOf(id), isTrue);
  });

  test('quem não edita a Ação não muda a restrição, e não recebe erro',
      () async {
    final id = await createGroupAction(
        conn, creatorId: _uidOwner, roundId: roundId, name: 'A4 alheia');

    expect(await setRestriction(_uidOutsider, id, true), 0);
    expect(await restrictionOf(id), isFalse);
  });

  test('Ação encerrada recusa mudança de restrição, inclusive de quem criou',
      () async {
    // O gatilho compara com `old.data_hora`, não com `acao_encerrada(id)`:
    // a versão por id passa pela RLS de quem escreve e devolveria NULL numa
    // Ação restrita invisível, deixando a trava falhar calada.
    final id = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      name: 'A4 encerrada',
      interval: "-interval '2 days'",
    );

    await expectLater(
      setRestriction(_uidOwner, id, true),
      throwsA(isA<ServerException>()),
    );
    expect(await restrictionOf(id), isFalse);
  });
}

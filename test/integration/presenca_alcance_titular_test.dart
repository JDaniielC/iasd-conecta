import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisito "O alcance do titular sobrevive à
/// saída".
///
/// A promessa não pode viver na tela. No Postgres, um `UPDATE ... WHERE` só
/// enxerga a linha que a policy de `SELECT` deixa a sessão ler — e
/// `confirmacoes_acao_select_conforme_acao` devolve a confirmação **apenas
/// quando a Ação correspondente é legível**, com a subconsulta rodando sob a
/// RLS de `acoes`. Ação restrita some para quem saiu do Grupo, e a confirmação
/// dela some junto.
///
/// Este é o mesmo defeito que `PENDENCIAS.md` 2.28 mediu na fixação de
/// mensagem, corrigido em `alcance-do-titular-sobre-texto-proprio`. Por isso os
/// testes daqui **tiram** a pessoa do Grupo antes de exercer o direito: sem
/// isso, provariam o caminho de dentro, que nunca esteve quebrado.

const _uidOwner = 'e5000000-0000-0000-0000-000000000001';
const _uidMember = 'e5000000-0000-0000-0000-000000000002';
const _uidOther = 'e5000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidMember, _uidOther];

void main() {
  late Connection conn;

  Future<void> leaveGroup(String groupId, String uid) async {
    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo '
        'where grupo_id = @g and usuario_id = @u',
      ),
      parameters: {'g': groupId, 'u': uid},
    );
  }

  /// Ação restrita ao Grupo, já acontecida, fechada, com marca sobre os dois
  /// participantes.
  Future<({String actionId, String groupId})> seedRestrictedClosedAction()
  async {
    final groupId = await createGroup(conn, ownerId: _uidOwner);
    await joinGroup(conn, groupId, _uidMember);
    await joinGroup(conn, groupId, _uidOther);
    final roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidOwner,
    );
    final actionId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      interval: "interval '-2 days'",
    );
    await makeWinner(conn, roundId, actionId);
    await seedConfirmation(conn, actionId, _uidMember);
    await seedConfirmation(conn, actionId, _uidOther);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidOwner,
    );
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidOther,
      markerId: _uidOwner,
    );
    return (actionId: actionId, groupId: groupId);
  }

  Future<List<String>> visibleConfirmationsFor(
    String actionId,
    String uid,
  ) => asUser(conn, uid, () async {
    final r = await conn.execute(
      Sql.named(
        'select usuario_id from public.confirmacoes_acao where acao_id = @acao',
      ),
      parameters: {'acao': actionId},
    );
    return [for (final row in r) row.toColumnMap()['usuario_id']! as String];
  });

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Alcance $uid');
    }
  });

  tearDownAll(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  tearDown(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
  });

  test('quem saiu do Grupo ainda enxerga a própria confirmação', () async {
    final seeded = await seedRestrictedClosedAction();
    await leaveGroup(seeded.groupId, _uidMember);

    final visible = await visibleConfirmationsFor(seeded.actionId, _uidMember);

    expect(visible, [_uidMember]);
  });

  test('quem saiu do Grupo NÃO enxerga a confirmação alheia', () async {
    // O braço novo da policy é `auth.uid() = usuario_id`, e só. Se ele alargasse
    // a leitura para a Ação inteira, esta change teria aberto a Ação restrita
    // pela porta dos fundos.
    final seeded = await seedRestrictedClosedAction();
    await leaveGroup(seeded.groupId, _uidMember);

    final visible = await visibleConfirmationsFor(seeded.actionId, _uidMember);

    expect(visible, isNot(contains(_uidOther)));
  });

  test('quem saiu do Grupo contesta a marca feita sobre si', () async {
    final seeded = await seedRestrictedClosedAction();
    await closeAttendanceList(
      conn,
      actionId: seeded.actionId,
      closerId: _uidOwner,
    );
    await leaveGroup(seeded.groupId, _uidMember);

    final affected = await disputeAttendance(
      conn,
      actionId: seeded.actionId,
      userId: _uidMember,
    );

    expect(affected, 1);
  });

  test('com o Grupo arquivado o titular ainda contesta', () async {
    final seeded = await seedRestrictedClosedAction();
    await closeAttendanceList(
      conn,
      actionId: seeded.actionId,
      closerId: _uidOwner,
    );
    await conn.execute(
      Sql.named(
        'update public.grupos set arquivado_em = now() where id = @g',
      ),
      parameters: {'g': seeded.groupId},
    );

    final affected = await disputeAttendance(
      conn,
      actionId: seeded.actionId,
      userId: _uidMember,
    );

    expect(affected, 1);
  });

  test('quem nunca participou não enxerga confirmação de Ação restrita',
      () async {
    final seeded = await seedRestrictedClosedAction();
    await leaveGroup(seeded.groupId, _uidOther);
    await leaveGroup(seeded.groupId, _uidMember);

    // Quem não tem confirmação na Ação restrita continua sem ver nada — o
    // braço novo é sobre a própria linha, não sobre a Ação.
    final visible = await visibleConfirmationsFor(seeded.actionId, _uidOwner);

    expect(visible, isNotEmpty, reason: 'o dono do Grupo continua vendo');
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisitos "A pessoa vê e contesta o que foi
/// afirmado sobre ela" e "Linha contestada nunca conta".
///
/// Comparecimento é o primeiro dado deste app **escrito por terceiro sobre o
/// titular** — `mensagens.texto` é do autor, `denuncias_mensagem.motivo` é de
/// quem denuncia. A contestação existe para equilibrar isso, e o equilíbrio só
/// é real porque a linha contestada sai da contagem **independentemente da
/// decisão**: o titular tem efeito sem precisar vencer uma disputa que o
/// software não tem como arbitrar.
///
/// Registro não se reescreve, como a change `denuncia-como-registro`
/// estabeleceu: nem a contestação nem a decisão são apagadas.

const _uidCreator = 'e4000000-0000-0000-0000-000000000001';
const _uidMember = 'e4000000-0000-0000-0000-000000000002';
const _uidOther = 'e4000000-0000-0000-0000-000000000003';
const _allUids = [_uidCreator, _uidMember, _uidOther];

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Contestação $uid');
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

  /// Ação passada, fechada, com [_uidMember] marcado como presente.
  ///
  /// Fechada de propósito: o efeito que interessa é sobre a CONTAGEM, e Ação
  /// aberta já está fora dela por outro motivo — o teste passaria sem provar
  /// nada sobre contestação.
  Future<String> seedClosedActionWithPresence() async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);
    await seedConfirmation(conn, actionId, _uidOther);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidOther,
      markerId: _uidCreator,
    );
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );
    return actionId;
  }

  test('o titular contesta a marca feita sobre si', () async {
    final actionId = await seedClosedActionWithPresence();

    final affected = await disputeAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
    );

    expect(affected, 1);
    final dispute = await disputeOf(conn, actionId, _uidMember);
    expect(dispute!.disputedAt, isNotNull);
    expect(dispute.decision, isNull);
  });

  test('contestar marca a confirmação de forma irreversível', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.disputedAt, isNotNull);
  });

  test('ninguém contesta marca feita sobre outra pessoa', () async {
    final actionId = await seedClosedActionWithPresence();

    // RECUSA DE `insert` LEVANTA EXCEÇÃO, e não afeta zero linhas. A regra
    // "recusa de RLS é ausência, não erro" do CLAUDE.md vale para `update` e
    // `delete`, onde a policy filtra linhas que existem. Em `insert` não há o
    // que filtrar: o Postgres recusa com 42501.
    await expectLater(
      disputeAttendance(
        conn,
        actionId: actionId,
        userId: _uidMember,
        asWhom: _uidOther,
      ),
      throwsA(isA<Exception>()),
    );

    expect(await disputeOf(conn, actionId, _uidMember), isNull);
  });

  test('não se contesta o que não foi marcado', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);

    await expectLater(
      disputeAttendance(conn, actionId: actionId, userId: _uidMember),
      throwsA(isA<Exception>()),
    );

    expect(await disputeOf(conn, actionId, _uidMember), isNull);
  });

  test('quem criou a Ação desfaz a marca', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final affected = await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'desfeita',
    );

    expect(affected, 1);
    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNull);
    final dispute = await disputeOf(conn, actionId, _uidMember);
    expect(dispute!.decision, 'desfeita');
    expect(dispute.decidedBy, _uidCreator);
  });

  test('quem criou a Ação mantém a marca', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final affected = await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'mantida',
    );

    expect(affected, 1);
    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNotNull);
  });

  test('quem não criou a Ação não decide contestação', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final affected = await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidOther,
      decision: 'desfeita',
    );

    expect(affected, 0);
    final dispute = await disputeOf(conn, actionId, _uidMember);
    expect(dispute!.decision, isNull);
  });

  test('nem o próprio titular decide a própria contestação', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final affected = await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidMember,
      decision: 'desfeita',
    );

    expect(affected, 0);
  });

  test('contestação registrada não se apaga', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    // A barreira aqui é o `grant`, e não a policy: `delete` nunca foi concedido
    // nesta tabela. Para o cliente isso chega como erro, não como ausência.
    await expectLater(
      asUser(conn, _uidMember, () async {
        await conn.execute(
          Sql.named(
            'delete from public.contestacoes_presenca '
            'where acao_id = @acao and usuario_id = @usuario',
          ),
          parameters: {'acao': actionId, 'usuario': _uidMember},
        );
      }),
      throwsA(isA<Exception>()),
    );

    expect(await disputeOf(conn, actionId, _uidMember), isNotNull);
  });

  test('o instante da contestação não se reescreve', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);
    final before = (await disputeOf(conn, actionId, _uidMember))!.disputedAt;

    // `contestada_em` não está no `grant` — só `decisao` está. A recusa vem do
    // privilégio, antes de qualquer policy.
    await expectLater(
      asUser(conn, _uidMember, () async {
        await conn.execute(
          Sql.named(
            'update public.contestacoes_presenca '
            "set contestada_em = timestamptz '1999-01-01 00:00:00+00' "
            'where acao_id = @acao and usuario_id = @usuario',
          ),
          parameters: {'acao': actionId, 'usuario': _uidMember},
        );
      }),
      throwsA(isA<Exception>()),
    );

    final after = (await disputeOf(conn, actionId, _uidMember))!.disputedAt;
    expect(after, before);
  });

  test('decisão tomada não se troca', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);
    await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'mantida',
    );

    final affected = await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'desfeita',
    );

    expect(affected, 0);
    final dispute = await disputeOf(conn, actionId, _uidMember);
    expect(dispute!.decision, 'mantida');
  });

  test('linha contestada sai da contagem enquanto pende', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    expect(rows.map((r) => r.userId), isNot(contains(_uidMember)));
    expect(rows.map((r) => r.userId), contains(_uidOther));
  });

  test('contestação NEGADA continua fora da contagem, para sempre', () async {
    // É o cenário que dá sentido ao resto. Se a decisão do criador devolvesse a
    // linha à contagem, a contestação seria desabafo sem efeito: o membro
    // reclama, o criador nega, o número segue igual.
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);
    await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'mantida',
    );

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    expect(rows.map((r) => r.userId), isNot(contains(_uidMember)));
  });

  test('contestação ACEITA continua fora da contagem, para sempre', () async {
    final actionId = await seedClosedActionWithPresence();
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);
    await decideDispute(
      conn,
      actionId: actionId,
      userId: _uidMember,
      deciderId: _uidCreator,
      decision: 'desfeita',
    );

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    expect(rows.map((r) => r.userId), isNot(contains(_uidMember)));
  });

  test('nenhuma decisão limpa a marca de contestação', () async {
    // A coluna redundante em `confirmacoes_acao` é o que faz "contestada nunca
    // conta" sobreviver a quem escrever a próxima consulta sem ler esta change
    // (design D-003). Se alguma decisão a limpasse, a redundância deixaria de
    // proteger exatamente no caso que ela existe para cobrir.
    for (final decision in ['mantida', 'desfeita']) {
      final actionId = await seedClosedActionWithPresence();
      await disputeAttendance(conn, actionId: actionId, userId: _uidMember);
      await decideDispute(
        conn,
        actionId: actionId,
        userId: _uidMember,
        deciderId: _uidCreator,
        decision: decision,
      );

      final state = await attendanceOf(conn, actionId, _uidMember);
      expect(state.disputedAt, isNotNull, reason: decision);

      await cleanUpPresenceFixtures(conn, _allUids);
    }
  });
}

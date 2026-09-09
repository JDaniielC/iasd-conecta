import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisito "Quem criou a Ação afirma quem esteve
/// nela".
///
/// O que esta change acrescenta ao app é a primeira afirmação de uma pessoa
/// SOBRE OUTRA. Por isso a autoridade de quem marca é o assunto do arquivo
/// inteiro: quem criou a Ação pode, e mais ninguém — nem quem participa, nem o
/// dono do Grupo da Ação.
///
/// Recusa de POLICY aqui é `affectedRows == 0`, nunca exceção. No Postgres,
/// uma policy que recusa faz a linha não existir para aquela sessão: o `update`
/// afeta zero linhas e volta com sucesso. Um teste que esperasse exceção
/// passaria pelo motivo errado, ou não passaria nunca (`CLAUDE.md`, "Recusa de
/// RLS é ausência, não erro").
///
/// A exceção à regra é o último teste, e ela é de `grant`, não de policy: `anon`
/// não tem `update` nesta tabela desde `fechar-superficie-anon`, e a requisição
/// para na porta do privilégio, antes de qualquer policy ser consultada.

const _uidCreator = 'e1000000-0000-0000-0000-000000000001';
const _uidMember = 'e1000000-0000-0000-0000-000000000002';
const _uidOutsider = 'e1000000-0000-0000-0000-000000000003';
const _uidGroupOwner = 'e1000000-0000-0000-0000-000000000004';
const _allUids = [_uidCreator, _uidMember, _uidOutsider, _uidGroupOwner];

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Presença $uid');
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

  test('quem criou a Ação marca o comparecimento de quem confirmou', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );

    expect(affected, 1);
    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNotNull);
    expect(state.markedBy, _uidCreator);
  });

  test('o instante e o autor vêm do banco, não do cliente', () async {
    // O cliente diz SE, o banco diz QUANDO e QUEM. Mesmo contrato de
    // `perfis_carimbar_consentimento`: um registro que valesse o que o cliente
    // afirma não demonstraria nada — aqui, deixaria alguém atribuir a outra
    // pessoa a afirmação que ele mesmo fez.
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);

    await asUser(conn, _uidCreator, () async {
      await conn.execute(
        Sql.named(
          'update public.confirmacoes_acao '
          "set compareceu_em = timestamptz '1999-01-01 00:00:00+00' "
          'where acao_id = @acao and usuario_id = @usuario',
        ),
        parameters: {'acao': actionId, 'usuario': _uidMember},
      );
    });

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt!.year, isNot(1999));
    expect(state.markedBy, _uidCreator);
  });

  test('quem participa da Ação não marca comparecimento', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);
    await seedConfirmation(conn, actionId, _uidOutsider);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidOutsider,
    );

    expect(affected, 0);
    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNull);
  });

  test('a pessoa não marca o próprio comparecimento', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidMember,
    );

    expect(affected, 0);
  });

  test('o dono do Grupo da Ação, que não a criou, não marca', () async {
    final groupId = await createGroup(conn, ownerId: _uidGroupOwner);
    await joinGroup(conn, groupId, _uidCreator);
    await joinGroup(conn, groupId, _uidMember);
    final roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidCreator,
    );
    final actionId = await createGroupAction(
      conn,
      creatorId: _uidCreator,
      roundId: roundId,
      interval: "interval '-2 days'",
    );
    await makeWinner(conn, roundId, actionId);
    await seedConfirmation(conn, actionId, _uidMember);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidGroupOwner,
    );

    expect(affected, 0);
  });

  test('não há comparecimento sobre quem não confirmou', () async {
    // Limite declarado da change: quem apareceu sem confirmar fica invisível, e
    // nunca ausente. Criar confirmação em nome de terceiro seria afirmar sobre
    // ele um ato que ele não praticou.
    final actionId = await createPastAction(conn, creatorId: _uidCreator);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidOutsider,
      markerId: _uidCreator,
    );

    expect(affected, 0);
  });

  test('não se marca comparecimento antes de a Ação acontecer', () async {
    final actionId = await createPastAction(
      conn,
      creatorId: _uidCreator,
      interval: "interval '5 days'",
    );
    await seedConfirmation(conn, actionId, _uidMember);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );

    expect(affected, 0);
  });

  test('não se marca comparecimento em Ação cancelada', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);
    await cancelAction(conn, actionId);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );

    expect(affected, 0);
  });

  test('quem criou desmarca enquanto a lista não fechou', () async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );

    final affected = await unmarkAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );

    expect(affected, 1);
    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNull);
    expect(state.markedBy, isNull);
  });

  test('sem sessão não se marca comparecimento', () async {
    // AQUI A RECUSA É EXCEÇÃO, e é a exceção certa. Para `anon` a barreira não
    // é a policy — é o `grant`, que a change `fechar-superficie-anon` revogou
    // desta tabela (20260816120100:96). A parte 1 desta change concedeu
    // `update (compareceu_em)` só a `authenticated`, de propósito.
    //
    // Não confundir com Visitante: `signInAnonymously` no arranque faz todo
    // Visitante chegar como `authenticated`. `anon` é a requisição sem
    // `Authorization` — `curl` com a chave publicável.
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidMember);

    await expectLater(
      asAnon(conn, () async {
        await conn.execute(
          Sql.named(
            'update public.confirmacoes_acao set compareceu_em = now() '
            'where acao_id = @acao and usuario_id = @usuario',
          ),
          parameters: {'acao': actionId, 'usuario': _uidMember},
        );
      }),
      throwsA(isA<Exception>()),
    );

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNull);
  });
}

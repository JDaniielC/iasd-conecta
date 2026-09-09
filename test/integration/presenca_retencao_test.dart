import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisito "A presença nominal tem prazo, o
/// agregado não".
///
/// Dois anos para a linha nominal, por faxina agendada, com rastro em
/// `execucoes_de_faxina` — inclusive quando não há nada a apagar, porque "rodou
/// e não havia nada" e "não rodou" são fatos diferentes (capability
/// `observador-de-retencao`).
///
/// A faxina **zera as colunas de presença** em vez de apagar a linha de
/// confirmação: apagar levaria junto a intenção, que é dado de outra finalidade
/// e de outro prazo. Zerar devolve a linha ao estado "não registrado", que a
/// change já define e já sabe tratar.

const _uidCreator = 'e8000000-0000-0000-0000-000000000001';
const _uidMember = 'e8000000-0000-0000-0000-000000000002';
const _uidLeaving = 'e8000000-0000-0000-0000-000000000003';
const _allUids = [_uidCreator, _uidMember, _uidLeaving];

void main() {
  late Connection conn;

  Future<int> runPurge() async {
    final r = await conn.execute(
      "select public.expurgar_presenca_vencida('app')",
    );
    return r.first[0]! as int;
  }

  Future<({int count, int erased})?> lastPurgeRun() async {
    final r = await conn.execute(
      "select quantas from public.execucoes_de_faxina "
      "where faxina = 'expurgar_presenca_vencida' "
      "order by quando desc limit 1",
    );
    if (r.isEmpty) return null;
    return (count: 1, erased: r.single.toColumnMap()['quantas']! as int);
  }

  /// Ação fechada com marca, [ageInDays] dias atrás.
  Future<String> seedClosedAction(int ageInDays) async {
    final actionId = await createPastAction(
      conn,
      creatorId: _uidCreator,
      interval: "interval '-$ageInDays days'",
    );
    await seedConfirmation(conn, actionId, _uidMember);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidCreator,
    );
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );
    return actionId;
  }

  Future<bool> confirmationExists(String actionId, String uid) async {
    final r = await conn.execute(
      Sql.named(
        'select 1 from public.confirmacoes_acao '
        'where acao_id = @acao and usuario_id = @usuario',
      ),
      parameters: {'acao': actionId, 'usuario': uid},
    );
    return r.isNotEmpty;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Retenção $uid');
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

  test('a faxina zera a presença de Ação com mais de dois anos', () async {
    final actionId = await seedClosedAction(800);

    await runPurge();

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNull);
    expect(state.markedBy, isNull);
    expect(state.disputedAt, isNull);
  });

  test('a linha de confirmação SOBREVIVE à faxina', () async {
    // Apagar a linha levaria junto a INTENÇÃO, que é dado de outra finalidade e
    // de outro prazo. O que vence é a afirmação de comparecimento.
    final actionId = await seedClosedAction(800);

    await runPurge();

    expect(await confirmationExists(actionId, _uidMember), isTrue);
  });

  test('presença dentro do prazo não é tocada', () async {
    final actionId = await seedClosedAction(400);

    await runPurge();

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.attendedAt, isNotNull);
  });

  test('a contagem congelada no fechamento sobrevive à faxina', () async {
    final actionId = await seedClosedAction(800);
    final before = await closingOf(conn, actionId);
    expect(before.presentAtClosing, 1);

    await runPurge();

    final after = await closingOf(conn, actionId);
    expect(after.presentAtClosing, 1);
    expect(after.closedAt, isNotNull);
  });

  test('a contestação vencida também vai embora', () async {
    final actionId = await seedClosedAction(800);
    await disputeAttendance(conn, actionId: actionId, userId: _uidMember);

    await runPurge();

    expect(await disputeOf(conn, actionId, _uidMember), isNull);
  });

  test('a execução fica registrada com a quantidade apagada', () async {
    await seedClosedAction(800);

    final erased = await runPurge();
    final run = await lastPurgeRun();

    expect(erased, greaterThanOrEqualTo(1));
    expect(run, isNotNull);
    expect(run!.erased, erased);
  });

  test('execução sem nada a apagar também fica registrada', () async {
    // "Rodou e não havia nada" e "não rodou" são fatos diferentes, e a
    // capability observador-de-retencao existe justamente porque o silêncio dos
    // dois era indistinguível.
    await runPurge();
    final before = await lastPurgeRun();

    final erased = await runPurge();
    final after = await lastPurgeRun();

    expect(erased, 0);
    expect(after, isNotNull);
    expect(after!.erased, 0);
    expect(before, isNotNull);
  });

  test('excluir a conta deixa o comparecimento sem nome', () async {
    // ACHADO, e é por isso que este teste existe em vez da presunção de que a
    // herança de perfis(id) resolve: `excluir_minha_conta` só APAGA confirmação
    // de Ação FUTURA (`a.data_hora > now()`, 20260806140000:132-134).
    // Comparecimento só existe em Ação passada, então a linha SOBREVIVE — o que
    // a protege é a anonimização do Perfil, o mesmo mecanismo de fixada_por e
    // removida_por.
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidLeaving);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidLeaving,
      markerId: _uidCreator,
    );

    await asUser(conn, _uidLeaving, () async {
      await conn.execute('select public.excluir_minha_conta()');
    });

    expect(await confirmationExists(actionId, _uidLeaving), isTrue);
    final r = await conn.execute(
      Sql.named('select nome_exibido from public.perfil_publico(@id)'),
      parameters: {'id': _uidLeaving},
    );
    expect(r.single.toColumnMap()['nome_exibido'], 'Membro removido');
  });

  test('quem marcou deixa de ser identificável ao excluir a conta', () async {
    final actionId = await createPastAction(conn, creatorId: _uidLeaving);
    await seedConfirmation(conn, actionId, _uidMember);
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidMember,
      markerId: _uidLeaving,
    );

    await asUser(conn, _uidLeaving, () async {
      await conn.execute('select public.excluir_minha_conta()');
    });

    final state = await attendanceOf(conn, actionId, _uidMember);
    expect(state.markedBy, _uidLeaving);
    final r = await conn.execute(
      Sql.named('select nome_exibido from public.perfil_publico(@id)'),
      parameters: {'id': _uidLeaving},
    );
    expect(r.single.toColumnMap()['nome_exibido'], 'Membro removido');
  });
}

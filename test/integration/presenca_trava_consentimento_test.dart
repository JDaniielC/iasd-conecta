import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisito "Sem consentimento da versão que
/// descreve a medição, não há registro".
///
/// A trava é na COLETA, não na consulta. Gravar primeiro e filtrar na hora de
/// medir guardaria por dois anos um dado provavelmente sensível do art. 5º, II
/// sobre quem nunca consentiu com a finalidade — e a Política vigente já promete
/// o contrário: *"o aceite dado numa versão não cobre finalidade nova que só a
/// versão seguinte passe a ter"* (`privacy_policy_page.dart`).
///
/// A checagem é `security definer` por necessidade, não por escolha:
/// `perfis_select_own` impede quem organiza a Ação de ler
/// `consentimento_lgpd_versao` de quem participa. Dentro de `security definer` a
/// RLS não se aplica, então o que precisa de checagem explícita é a autoridade
/// de quem chamou — e é o que os dois últimos testes deste arquivo exercem.

const _uidCreator = 'e6000000-0000-0000-0000-000000000001';
const _uidUpToDate = 'e6000000-0000-0000-0000-000000000002';
const _uidOutdated = 'e6000000-0000-0000-0000-000000000003';
const _uidUnknown = 'e6000000-0000-0000-0000-000000000004';
const _uidStranger = 'e6000000-0000-0000-0000-000000000005';
const _allUids = [
  _uidCreator,
  _uidUpToDate,
  _uidOutdated,
  _uidUnknown,
  _uidStranger,
];

void main() {
  late Connection conn;

  Future<bool> canRegisterAttendance({
    required String actionId,
    required String userId,
    required String callerId,
  }) => asUser(conn, callerId, () async {
    final r = await conn.execute(
      Sql.named('select public.pode_registrar_presenca(@acao, @usuario)'),
      parameters: {'acao': actionId, 'usuario': userId},
    );
    return r.first[0]! as bool;
  });

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Trava $uid');
    }
    // Nascem com a versão vigente, carimbada pelo gatilho. Só estes dois são
    // empurrados para trás.
    await setConsentVersion(conn, _uidOutdated, '0.0-anterior');
    await setConsentVersion(conn, _uidUnknown, null);
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

  Future<String> seedActionWith(List<String> confirmedUids) async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    for (final uid in confirmedUids) {
      await seedConfirmation(conn, actionId, uid);
    }
    return actionId;
  }

  test('quem está com a versão vigente é marcado normalmente', () async {
    final actionId = await seedActionWith([_uidUpToDate]);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidUpToDate,
      markerId: _uidCreator,
    );

    expect(affected, 1);
  });

  test('não se marca comparecimento de quem está com versão anterior',
      () async {
    final actionId = await seedActionWith([_uidOutdated]);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidOutdated,
      markerId: _uidCreator,
    );

    expect(affected, 0);
    final state = await attendanceOf(conn, actionId, _uidOutdated);
    expect(state.attendedAt, isNull);
  });

  test('versão desconhecida fica de fora por default', () async {
    // São os aceites colhidos entre 2026-07-23 e 2026-08-09, quando o app só
    // gravava a data. `NULL` significa desconhecida e mais nada — errar para o
    // lado de não coletar é o lado certo de errar.
    final actionId = await seedActionWith([_uidUnknown]);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidUnknown,
      markerId: _uidCreator,
    );

    expect(affected, 0);
  });

  test('depois do reaceite, a marca passa', () async {
    final actionId = await seedActionWith([_uidOutdated]);
    expect(
      await markAttendance(
        conn,
        actionId: actionId,
        userId: _uidOutdated,
        markerId: _uidCreator,
      ),
      0,
      reason: 'antes do reaceite',
    );

    final reaccepted = await reacceptLegalText(conn, _uidOutdated);
    expect(reaccepted, 1);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidOutdated,
      markerId: _uidCreator,
    );

    expect(affected, 1);

    // Devolve o Perfil ao estado defasado para os testes seguintes.
    await setConsentVersion(conn, _uidOutdated, '0.0-anterior');
  });

  test('o reaceite carimba a versão vigente, não a que o cliente mandar',
      () async {
    await setConsentVersion(conn, _uidStranger, '0.0-anterior');
    await asUser(conn, _uidStranger, () async {
      await conn.execute(
        Sql.named(
          'update public.perfis set consentimento_lgpd_aceito_em = now() '
          'where id = @id',
        ),
        parameters: {'id': _uidStranger},
      );
    });

    final version = await consentVersionOf(conn, _uidStranger);
    final r = await conn.execute('select public.versao_texto_legal_vigente()');
    expect(version, r.first[0]);
  });

  test('a checagem recusa quem não criou a Ação', () async {
    final actionId = await seedActionWith([_uidUpToDate]);

    final allowed = await canRegisterAttendance(
      actionId: actionId,
      userId: _uidUpToDate,
      callerId: _uidStranger,
    );

    expect(allowed, isFalse);
  });

  test('a checagem recusa consulta sobre quem não tem confirmação na Ação',
      () async {
    // Sem este braço, a função vira oráculo geral de "fulano está com o aceite
    // atrasado" para qualquer pessoa que crie uma Ação qualquer.
    final actionId = await seedActionWith([_uidUpToDate]);

    final allowed = await canRegisterAttendance(
      actionId: actionId,
      userId: _uidStranger,
      callerId: _uidCreator,
    );

    expect(allowed, isFalse);
  });

  test('ninguém lê a versão aceita por outra pessoa', () async {
    // Achado C-5 da convergência 1. A garantia vem de `perfis_select_own`, que
    // é anterior a esta change e não foi tocada por ela — o teste existe para
    // que uma policy futura não a desfaça em silêncio, agora que a versão
    // aceita passou a decidir se um dado é coletado.
    final rows = await asUser(conn, _uidCreator, () async {
      final r = await conn.execute(
        Sql.named(
          'select consentimento_lgpd_versao from public.perfis where id = @id',
        ),
        parameters: {'id': _uidOutdated},
      );
      return r.length;
    });

    expect(rows, 0);
  });

  test('a própria pessoa lê a própria versão', () async {
    final rows = await asUser(conn, _uidOutdated, () async {
      final r = await conn.execute(
        Sql.named(
          'select consentimento_lgpd_versao from public.perfis where id = @id',
        ),
        parameters: {'id': _uidOutdated},
      );
      return [for (final row in r) row.toColumnMap()];
    });

    expect(rows.length, 1);
    expect(rows.single['consentimento_lgpd_versao'], '0.0-anterior');
  });

  test('sem sessão a checagem nem é executável', () async {
    // `anon` não tem `execute`: a change `revogar-execute-de-public` tirou o
    // default do Postgres, e esta função foi concedida só a `authenticated`.
    // A requisição para no privilégio, antes de a função rodar — que é mais
    // forte do que devolver `false`, porque nem chega a consultar o aceite de
    // ninguém.
    final actionId = await seedActionWith([_uidUpToDate]);

    await expectLater(
      asAnon(conn, () async {
        await conn.execute(
          Sql.named('select public.pode_registrar_presenca(@acao, @usuario)'),
          parameters: {'acao': actionId, 'usuario': _uidUpToDate},
        );
      }),
      throwsA(isA<Exception>()),
    );
  });
}

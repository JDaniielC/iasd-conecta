import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisitos "Não marcado significa não registrado,
/// nunca ausente" e "A ausência só nasce de um fechamento explícito".
///
/// É o coração da change. Sem esta distinção, toda Ação em que quem organiza
/// esqueceu de marcar produziria um Grupo inteiro de ausentes — e como o
/// esquecimento é mais provável em Grupo desorganizado, o erro cairia justo
/// sobre os Grupos que a liderança mais quer entender.
///
/// O que se afirma aqui é `public.presencas_computaveis` (design D-009), que é
/// o único lugar onde "esta linha conta" está escrito. Afirmar sobre as colunas
/// cruas provaria que o dado foi gravado, não que ele conta — e é o segundo
/// que a spec promete.

const _uidCreator = 'e2000000-0000-0000-0000-000000000001';
const _uidPresent = 'e2000000-0000-0000-0000-000000000002';
const _uidAbsent = 'e2000000-0000-0000-0000-000000000003';
const _uidStranger = 'e2000000-0000-0000-0000-000000000004';
const _allUids = [_uidCreator, _uidPresent, _uidAbsent, _uidStranger];

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Fechamento $uid');
    }
  });

  tearDownAll(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
    // O Administrador semeado num dos testes referencia `perfis`, e a FK recusa
    // apagar o Perfil antes dele.
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito '
        'where usuario_id = any(@ids::uuid[])',
      ),
      parameters: {'ids': _allUids},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  tearDown(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
  });

  /// Ação que já aconteceu, com duas pessoas confirmadas.
  Future<String> seedPastActionWithTwo() async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, _uidPresent);
    await seedConfirmation(conn, actionId, _uidAbsent);
    return actionId;
  }

  test('Ação passada sem marca nenhuma não produz ausente', () async {
    final actionId = await seedPastActionWithTwo();

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    // As duas asserções são separadas de propósito. "Ninguém consta como
    // ausente" e "a Ação não entra na contagem" são fatos diferentes, e um
    // teste que afirmasse só o primeiro passaria por metade do motivo.
    expect(rows.where((r) => !r.present), isEmpty, reason: 'numerador');
    expect(rows, isEmpty, reason: 'denominador');
  });

  test('marca parcial sem fechamento continua fora da contagem', () async {
    final actionId = await seedPastActionWithTwo();
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    expect(rows, isEmpty);
    // A marca existe na tabela; o que não existe é a contagem.
    final state = await attendanceOf(conn, actionId, _uidPresent);
    expect(state.attendedAt, isNotNull);
  });

  test('o fechamento converte o que sobrou em ausência', () async {
    final actionId = await seedPastActionWithTwo();
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );

    final affected = await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );
    expect(affected, 1);

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );
    // Três, e não dois: quem cria uma Ação entra confirmado nela por gatilho
    // (`criar_confirmacao_do_criador`, feature 004). O criador não se marcou,
    // então o fechamento o conta como ausente — o que está certo e é o próprio
    // ponto do requisito.
    expect(rows.length, 3);
    expect(rows.firstWhere((r) => r.userId == _uidPresent).present, isTrue);
    expect(rows.firstWhere((r) => r.userId == _uidAbsent).present, isFalse);
    expect(rows.firstWhere((r) => r.userId == _uidCreator).present, isFalse);
  });

  test('a contagem de presentes é congelada no fechamento', () async {
    final actionId = await seedPastActionWithTwo();
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );

    final closing = await closingOf(conn, actionId);
    expect(closing.closedAt, isNotNull);
    expect(closing.presentAtClosing, 1);
  });

  test('não se fecha a lista antes de a Ação acontecer', () async {
    // Quem criou passa pela RLS de `acoes` — a linha existe para a sessão. Quem
    // recusa aqui é o gatilho, e por isso a recusa é exceção.
    final actionId = await createPastAction(
      conn,
      creatorId: _uidCreator,
      interval: "interval '5 days'",
    );

    await expectLater(
      closeAttendanceList(
        conn,
        actionId: actionId,
        closerId: _uidCreator,
      ),
      throwsA(isA<Exception>()),
    );

    final closing = await closingOf(conn, actionId);
    expect(closing.closedAt, isNull);
  });

  test('quem não criou a Ação não fecha a lista', () async {
    // Aqui quem recusa é a RLS: `acoes_update_criador_dono_grupo_ou_admin` não
    // alcança quem só participa, então a linha não existe para a sessão e o
    // update afeta zero.
    final actionId = await seedPastActionWithTwo();

    final affected = await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidPresent,
    );

    expect(affected, 0);
  });

  test('nem o Administrador do distrito fecha a lista', () async {
    // ESTE É O BURACO QUE A RLS NÃO TAPA, e por isso o gatilho existe.
    // `acoes` tem `grant update` de tabela inteira (20260723230639:114) e a
    // policy aceita criador OU dono do Grupo OU Administrador
    // (20260724092132:95-110). Os dois últimos passariam pela RLS e fechariam
    // lista de Ação alheia. Aqui a recusa é EXCEÇÃO, não linha ausente: a
    // policy deixou a linha visível, então zerar `affectedRows` seria mentira —
    // e uma tela que lesse zero como "não tinha o que fechar" afirmaria errado.
    await createTestDistrictAdmin(conn, _uidStranger);
    final actionId = await seedPastActionWithTwo();

    await expectLater(
      closeAttendanceList(
        conn,
        actionId: actionId,
        closerId: _uidStranger,
      ),
      throwsA(isA<Exception>()),
    );

    final closing = await closingOf(conn, actionId);
    expect(closing.closedAt, isNull);
  });

  test('lista fechada não aceita marca nova', () async {
    final actionId = await seedPastActionWithTwo();
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );

    expect(affected, 0);
    final state = await attendanceOf(conn, actionId, _uidPresent);
    expect(state.attendedAt, isNull);
  });

  test('lista fechada não aceita remoção de marca', () async {
    final actionId = await seedPastActionWithTwo();
    await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );

    final affected = await unmarkAttendance(
      conn,
      actionId: actionId,
      userId: _uidPresent,
      markerId: _uidCreator,
    );

    expect(affected, 0);
    final state = await attendanceOf(conn, actionId, _uidPresent);
    expect(state.attendedAt, isNotNull);
  });

  test('lista fechada não reabre', () async {
    final actionId = await seedPastActionWithTwo();
    await closeAttendanceList(
      conn,
      actionId: actionId,
      closerId: _uidCreator,
    );

    await expectLater(
      asUser(conn, _uidCreator, () async {
        await conn.execute(
          Sql.named(
            'update public.acoes set presenca_fechada_em = null where id = @acao',
          ),
          parameters: {'acao': actionId},
        );
      }),
      throwsA(isA<Exception>()),
    );

    final closing = await closingOf(conn, actionId);
    expect(closing.closedAt, isNotNull);
  });

  test('Ação antiga nunca fechada segue fora da contagem', () async {
    final actionId = await createPastAction(
      conn,
      creatorId: _uidCreator,
      interval: "interval '-400 days'",
    );
    await seedConfirmation(conn, actionId, _uidPresent);

    final rows = await computableRowsFor(
      conn,
      actionId: actionId,
      readerId: _uidCreator,
    );

    expect(rows, isEmpty);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — o prazo de 30 dias, cumprido de verdade.
///
/// O prazo é PROMESSA na Política de Privacidade, e promessa de prazo só vale
/// se alguém apagar. Este teste é o que separa "a função existe" de "a função
/// apaga o certo e só o certo".
///
/// A fronteira é `acoes.data_hora + 30 dias`, não a criação da mensagem: o que
/// dá sentido à conversa é o encontro. Os dois lados dela são testados, porque
/// um `>` trocado por `<` passa em qualquer teste que só olhe um lado.
///
/// Chat de GRUPO nunca expira, e Grupo arquivado menos ainda — o histórico é
/// justamente o que sobra de um Grupo arquivado.
///
/// CUIDADO AO MEXER: `expurgar_mensagens_de_acao()` é GLOBAL — roda como dono e
/// varre toda a tabela, não só as linhas deste arquivo. Por isso as asserções
/// são sobre linhas identificadas por id, nunca sobre o número que a função
/// devolve: `dart test` roda os arquivos em paralelo e aquele número é de todo
/// mundo.

const _uidCreator = 'b1000000-0000-0000-0000-000000000001';
const _uidOwner = 'b1000000-0000-0000-0000-000000000002';
const _uidReporter = 'b1000000-0000-0000-0000-000000000003';
const _allUids = [_uidCreator, _uidOwner, _uidReporter];

void main() {
  late Connection conn;
  late String oldAction, yesterdayAction, liveGroup, archivedGroup;
  late String oldMessage, yesterdayMessage, groupMessage, archivedGroupMessage;
  late String pendingReport, resolvedReport;

  Future<bool> exists(String messageId) async {
    final r = await conn.execute(
      Sql.named('select 1 from public.mensagens where id = @m'),
      parameters: {'m': messageId},
    );
    return r.isNotEmpty;
  }

  Future<Map<String, dynamic>> reportRow(String id) async {
    final r = await conn.execute(
      Sql.named(
        'select estado, motivo, mensagem_id::text, resolvida_em '
        'from public.denuncias_mensagem where id = @d',
      ),
      parameters: {'d': id},
    );
    return r.single.toColumnMap();
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: 30,
      );
    }

    oldAction = await createLooseAction(
      conn,
      creatorId: _uidCreator,
      name: 'Ação B1 de 31 dias atrás',
      interval: "interval '-31 days'",
    );
    yesterdayAction = await createLooseAction(
      conn,
      creatorId: _uidCreator,
      name: 'Ação B1 de ontem',
      interval: "interval '-1 days'",
    );

    liveGroup = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo B1');
    archivedGroup = await createGroup(
      conn,
      ownerId: _uidOwner,
      name: 'Grupo B1 arquivado',
    );
    await conn.execute(
      Sql.named('update public.grupos set arquivado_em = now() where id = @g'),
      parameters: {'g': archivedGroup},
    );

    oldMessage = await seedMessage(
      conn,
      authorId: _uidCreator,
      actionId: oldAction,
      text: 'combinado de 31 dias',
    );
    yesterdayMessage = await seedMessage(
      conn,
      authorId: _uidCreator,
      actionId: yesterdayAction,
      text: 'combinado de ontem',
    );
    groupMessage = await seedMessage(
      conn,
      authorId: _uidOwner,
      groupId: liveGroup,
      text: 'conversa do Grupo',
    );
    archivedGroupMessage = await seedMessage(
      conn,
      authorId: _uidOwner,
      groupId: archivedGroup,
      text: 'o que sobrou do Grupo',
    );

    final p = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d) '
        'returning id',
      ),
      parameters: {
        'm': oldMessage,
        'mo': 'ofensa que ficou sem julgamento',
        'd': _uidReporter,
      },
    );
    pendingReport = p.single.toColumnMap()['id']! as String;

    final r = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        "(mensagem_id, motivo, denunciante_id, estado, resolvida_em) "
        "values (@m, @mo, @d, 'improcedente', now()) returning id",
      ),
      parameters: {
        'm': oldMessage,
        'mo': 'denúncia já julgada antes do expurgo',
        'd': _uidReporter,
      },
    );
    resolvedReport = r.single.toColumnMap()['id']! as String;

    // O expurgo roda UMA vez, no setUp: se cada teste chamasse, a ordem entre
    // eles passaria a importar e o arquivo deixaria de ser determinístico.
    await conn.execute('select public.expurgar_mensagens_de_acao()');
    // A fumaça é sobre a linha DESTE arquivo, e não sobre o número que a função
    // devolve — o mesmo cuidado que o cabeçalho pede e que esta linha
    // desobedecia. `expurgar_mensagens_de_acao()` é global e roda em paralelo
    // com outros arquivos: desde `mensagem-fixada` há um segundo arquivo que a
    // chama, e ele pode levar a linha vencida antes daqui, deixando o número
    // em zero sem que nada esteja errado. Medido em 2026-08-17.
    expect(
      await exists(oldMessage),
      isFalse,
      reason: 'sem nada apagado, o resto deste arquivo não prova nada',
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.denuncias_mensagem where id = any(@ds::uuid[])',
      ),
      parameters: {
        'ds': [pendingReport, resolvedReport],
      },
    );
    for (final g in [liveGroup, archivedGroup]) {
      await clearGroupChat(conn, g);
    }
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where acao_id = any(@as::uuid[])',
      ),
      parameters: {
        'as': [oldAction, yesterdayAction],
      },
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = any(@as::uuid[])'),
      parameters: {
        'as': [oldAction, yesterdayAction],
      },
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = any(@gs::uuid[])'),
      parameters: {
        'gs': [liveGroup, archivedGroup],
      },
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('Ação de 31 dias atrás perde as mensagens', () async {
    expect(await exists(oldMessage), isFalse);
  });

  test('Ação de ontem mantém — a fronteira é data_hora + 30 dias', () async {
    expect(await exists(yesterdayMessage), isTrue);
  });

  test('mensagem de Grupo nunca some, nem em Grupo arquivado', () async {
    expect(await exists(groupMessage), isTrue);
    expect(
      await exists(archivedGroupMessage),
      isTrue,
      reason: 'o histórico é justamente o que sobra de um Grupo arquivado',
    );
  });

  test(
    'a Ação sobrevive ao expurgo — some a conversa, não o encontro',
    () async {
      final r = await conn.execute(
        Sql.named('select 1 from public.acoes where id = @a'),
        parameters: {'a': oldAction},
      );
      expect(r, isNotEmpty);
    },
  );

  test(
    'denúncia pendente vira sem_mensagem, com o motivo preservado',
    () async {
      final d = await reportRow(pendingReport);
      expect(d['estado'], 'sem_mensagem');
      expect(
        d['motivo'],
        'ofensa que ficou sem julgamento',
        reason: 'o motivo escrito por quem denunciou é o registro do caso',
      );
      expect(
        d['mensagem_id'],
        isNull,
        reason: 'on delete SET NULL, não cascade — a denúncia não some junto',
      );
      expect(d['resolvida_em'], isNotNull);
    },
  );

  test('denúncia já julgada não é reescrita pelo expurgo', () async {
    final d = await reportRow(resolvedReport);
    expect(
      d['estado'],
      'improcedente',
      reason: 'o gatilho só alcança quem estava pendente',
    );
    expect(d['motivo'], 'denúncia já julgada antes do expurgo');
  });
}

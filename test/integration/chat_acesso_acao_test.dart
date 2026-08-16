import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — quem lê o chat de uma Ação.
///
/// O chat de Ação é de quem VAI: confirmação em qualquer status, mais o criador
/// e o dono do Grupo dela. Participar do Grupo não basta — quem não confirmou
/// não está combinando aquele encontro.
///
/// O último caso é o que prova o `security invoker` das funções de acesso: numa
/// Ação restrita ao Grupo, quem não participa do Grupo lê 0 mensagens **sem uma
/// linha de código aqui**, porque `pode_ver_chat_acao` enxerga `acoes` sob a RLS
/// de quem chamou e a Ação simplesmente não existe para essa pessoa. Se alguém
/// uniformizar as três funções para `definer`, é este teste que fica vermelho.

const _uidCreator = 'ad000000-0000-0000-0000-000000000001';
const _uidConfirmed = 'ad000000-0000-0000-0000-000000000002';
const _uidQueued = 'ad000000-0000-0000-0000-000000000003';
const _uidGroupOnly = 'ad000000-0000-0000-0000-000000000004';
const _uidOutsider = 'ad000000-0000-0000-0000-000000000005';
const _allUids = [
  _uidCreator,
  _uidConfirmed,
  _uidQueued,
  _uidGroupOnly,
  _uidOutsider,
];

void main() {
  late Connection conn;
  late String groupId, roundId, actionId, restrictedId;

  Future<void> confirm(String uid, String action) =>
      asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) '
            'values (@a, @u)',
          ),
          parameters: {'a': action, 'u': uid},
        );
      });

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
    groupId = await createGroup(conn, ownerId: _uidCreator, name: 'Grupo AD');
    for (final uid in [_uidConfirmed, _uidQueued, _uidGroupOnly]) {
      await joinGroup(conn, groupId, uid);
    }

    // Duas vagas: o gatilho já ocupa uma com quem criou, sobra uma.
    final r = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, "
        "limite_vagas) values ('Ação AD', now() + interval '5 days', 'Sede', "
        "@c, 2) returning id",
      ),
      parameters: {'c': _uidCreator},
    );
    actionId = r.single.toColumnMap()['id']! as String;
    await confirm(_uidConfirmed, actionId);
    await confirm(_uidQueued, actionId); // estoura o limite, cai na fila
    await seedMessage(conn, authorId: _uidCreator, actionId: actionId);

    // Ação restrita, que só existe como candidata de Rodada.
    roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidCreator,
    );
    restrictedId = await createGroupAction(
      conn,
      creatorId: _uidCreator,
      roundId: roundId,
      restricted: true,
      name: 'Restrita AD',
    );
    await seedMessage(conn, authorId: _uidCreator, actionId: restrictedId);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.mensagens where acao_id in (@a, @r)'),
      parameters: {'a': actionId, 'r': restrictedId},
    );
    await conn.execute(
      Sql.named(
        'update public.rodadas_votacao set vencedora_id = null where id = @r',
      ),
      parameters: {'r': roundId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.confirmacoes_acao where acao_id in (@a, @r)',
      ),
      parameters: {'a': actionId, 'r': restrictedId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id in (@a, @r)'),
      parameters: {'a': actionId, 'r': restrictedId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where id = @r'),
      parameters: {'r': roundId},
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

  test('confirmada lê; quem está na fila lê E escreve', () async {
    expect(
      await asUser(
        conn,
        _uidConfirmed,
        () => visibleMessageCount(conn, actionId: actionId),
      ),
      greaterThan(0),
    );
    final status = await conn.execute(
      Sql.named(
        'select status from public.confirmacoes_acao '
        'where acao_id = @a and usuario_id = @u',
      ),
      parameters: {'a': actionId, 'u': _uidQueued},
    );
    expect(status.single.toColumnMap()['status'], 'fila');
    final id = await asUser(
      conn,
      _uidQueued,
      () => writeMessage(conn, authorId: _uidQueued, actionId: actionId),
    );
    expect(id, isNotEmpty, reason: 'quem está na fila também vai combinar');
  });

  test('participar do Grupo não basta — sem confirmar, lê 0 da Ação', () async {
    expect(
      await asUser(
        conn,
        _uidGroupOnly,
        () => visibleMessageCount(conn, actionId: actionId),
      ),
      0,
    );
    await seedMessage(conn, authorId: _uidCreator, groupId: groupId);
    expect(
      await asUser(
        conn,
        _uidGroupOnly,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      greaterThan(0),
      reason: 'e continua lendo o chat do Grupo',
    );
  });

  test(
    'quem criou lê e escreve sem ter confirmado nada além do automático',
    () async {
      expect(
        await asUser(
          conn,
          _uidCreator,
          () => visibleMessageCount(conn, actionId: actionId),
        ),
        greaterThan(0),
      );
    },
  );

  test('quem desconfirma deixa de ler', () async {
    await asUser(conn, _uidConfirmed, () async {
      await conn.execute(
        Sql.named(
          'delete from public.confirmacoes_acao '
          'where acao_id = @a and usuario_id = @u',
        ),
        parameters: {'a': actionId, 'u': _uidConfirmed},
      );
    });
    expect(
      await asUser(
        conn,
        _uidConfirmed,
        () => visibleMessageCount(conn, actionId: actionId),
      ),
      0,
    );
  });

  test(
    'Ação restrita: quem não participa do Grupo lê 0, mesmo sendo adulto',
    () async {
      // Este é o teste do `security invoker`. A Ação some para quem é de fora, a
      // confirmação some junto, e `pode_ver_chat_acao` devolve falso sozinho.
      expect(await asUser(conn, _uidOutsider, () => isOfAge(conn)), isTrue);
      expect(
        await asUser(
          conn,
          _uidOutsider,
          () => visibleMessageCount(conn, actionId: restrictedId),
        ),
        0,
      );
      expect(
        await asUser(
          conn,
          _uidCreator,
          () => visibleMessageCount(conn, actionId: restrictedId),
        ),
        greaterThan(0),
        reason: 'quem participa e criou continua lendo',
      );
    },
  );
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — cancelar a Ação NÃO fecha a conversa dela.
///
/// Convergência 1. O comportamento sempre esteve certo e nenhum teste o
/// segurava, o que é pior do que parece: `pode_ver_chat_acao` é
/// `security invoker`, e isso é uma escolha — é o que faz o chat herdar sozinho
/// a restrição de `acao-direcionada-a-grupo`, sem uma linha de código a mais.
/// O preço da escolha é que QUALQUER aperto futuro na policy de `acoes` apaga a
/// conversa correspondente, em silêncio, sem erro e sem teste vermelho.
///
/// Uma policy que escondesse Ação cancelada — decisão perfeitamente defensável
/// noutro contexto — mataria o chat exatamente quando ele mais importa. A spec
/// diz o porquê numa linha: "cancelar é justamente quando mais se precisa
/// avisar". Quem tinha reservado o carro precisa saber que não vai mais.
///
/// Este arquivo é o alarme dessa herança.

const _uidCreator = '18000000-0000-0000-0000-000000000001';
const _uidConfirmed = '18000000-0000-0000-0000-000000000002';
const _allUids = [_uidCreator, _uidConfirmed];

void main() {
  late Connection conn;
  late String actionId, seededId;

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
    actionId = await createLooseAction(
      conn,
      creatorId: _uidCreator,
      name: 'Ação C5 que será cancelada',
    );
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) '
        'values (@a, @u) on conflict do nothing',
      ),
      parameters: {'a': actionId, 'u': _uidConfirmed},
    );
    seededId = await seedMessage(
      conn,
      authorId: _uidCreator,
      actionId: actionId,
      text: 'quem leva o som?',
    );

    // O cancelamento vem DEPOIS da confirmação de propósito: o gatilho de
    // `confirmacoes_acao` recusa confirmar presença em Ação cancelada, então
    // montar na ordem inversa faria o cenário nem existir.
    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @a'),
      parameters: {'a': actionId},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.mensagens where acao_id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('quem confirmou continua LENDO o chat da Ação cancelada', () async {
    expect(
      await asUser(conn, _uidConfirmed, () async {
        final r = await conn.execute(
          Sql.named('select public.pode_ver_chat_acao(@a)'),
          parameters: {'a': actionId},
        );
        return r.first[0]! as bool;
      }),
      isTrue,
    );
    expect(
      await asUser(
        conn,
        _uidConfirmed,
        () => visibleMessageCount(conn, actionId: actionId),
      ),
      1,
    );
  });

  test(
    'e continua ESCREVENDO — cancelar é quando mais se precisa avisar',
    () async {
      final id = await asUser(
        conn,
        _uidConfirmed,
        () => writeMessage(
          conn,
          authorId: _uidConfirmed,
          actionId: actionId,
          text: 'então não vou mais precisar do carro',
        ),
      );
      expect(id, isNotEmpty);
      expect(
        await asUser(
          conn,
          _uidConfirmed,
          () => visibleMessageCount(conn, actionId: actionId),
        ),
        2,
      );
    },
  );

  test('a mensagem anterior ao cancelamento não some', () async {
    expect((await messageStateOf(conn, seededId)).hasText, isTrue);
  });
}

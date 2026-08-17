import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `filtro-e-intervalo-de-mensagem`, tarefa 2.4 — a mensagem recusada
/// não gera EVENTO NENHUM no canal de tempo real.
///
/// É a razão de a recusa ser `before insert` e não uma limpeza posterior. Uma
/// mensagem gravada e removida depois já saiu: o canal entrega a linha no
/// momento em que ela passa a existir, e quem estava com o chat aberto leu.
/// Nenhum teste de policy pega isso — a linha some da consulta e a suíte fica
/// verde enquanto o texto já foi entregue.
///
/// Fala com o servidor de Realtime de verdade (WebSocket na 54321), como
/// `chat_realtime_test.dart`. Não dá para provar o canal sem usar o canal.
///
/// A JANELA DE ESPERA sai do mesmo desenho daquele arquivo: o aquecimento
/// CRONOMETRA quanto a entrega leva nesta máquina, e a espera da não entrega é
/// 5× isso, com piso de 3 segundos. Ausência medida com pressa é só
/// impaciência.

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

/// Só na lista de conversa, e só deste arquivo.
const _blocked = 'zurupo';

void main() {
  late Connection conn;
  late SupabaseClient client;
  late String uid;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await lockBlockedWordList(conn);
    await conn.execute(
      Sql.named(
        'insert into public.palavras_bloqueadas_mensagem (palavra) values (@p) '
        'on conflict do nothing',
      ),
      parameters: {'p': _blocked},
    );

    // Sessão REAL: o canal valida um JWT assinado, então `set
    // request.jwt.claims` no Postgres não serve.
    client = SupabaseClient(_url, _publishableKey);
    uid = (await client.auth.signInAnonymously()).session!.user.id;
    await createTestProfileWithAge(conn, uid, name: 'Autor FR', age: 30);
    groupId = await createGroup(conn, ownerId: uid, name: 'Grupo FR');
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.palavras_bloqueadas_mensagem where palavra = @p',
      ),
      parameters: {'p': _blocked},
    );
    await cleanUpTestUser(conn, uid);
    await client.dispose();
    await conn.close();
  });

  test('a mensagem recusada pelo filtro não chega ao canal', () async {
    final received = <String>[];

    final ready = Completer<void>();
    client
        .channel('chat-filtro-fr')
        .onPostgresChanges(
          // `all` e não `insert`: um gatilho que gravasse e limpasse depois
          // produziria `insert` seguido de `update`. Os dois reprovam este
          // caso, e é o ponto.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mensagens',
          // FILTRADO POR GRUPO, como o app filtra (`ChatNotifier._openChannel`).
          // Sem o filtro este caso é FLAKY na suíte paralela: evento de
          // `delete` chega a todo assinante da tabela, porque o registro antigo
          // só carrega a chave primária e não há `grupo_id` no que a RLS possa
          // olhar. A limpeza de qualquer outro arquivo de teste caía aqui.
          //
          // Filtrar não enfraquece a prova: para uma mensagem ser apagada ela
          // precisa antes ter sido INSERIDA, e o insert passa pelo filtro.
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'grupo_id',
            value: groupId,
          ),
          callback: (payload) => received.add(
            '${payload.eventType}:${payload.newRecord['texto'] ?? payload.oldRecord['id']}',
          ),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              !ready.isCompleted) {
            ready.complete();
          }
        });
    await ready.future;

    // AQUECIMENTO. Logo depois de `supabase db reset` o servidor de Realtime
    // ainda não pegou a publicação nova e o cliente já reporta SUBSCRIBED assim
    // mesmo. Sem aquecer, "não recebeu nada" passaria também com o canal morto
    // — o teste diria "recusa silenciosa" quando a verdade é "canal desligado".
    final clock = Stopwatch()..start();
    var deliveryTime = Duration.zero;
    var alive = false;
    for (var attempt = 0; attempt < 20 && !alive; attempt++) {
      clock.reset();
      await seedMessage(
        conn,
        authorId: uid,
        groupId: groupId,
        text: 'aquecimento',
      );
      for (var wait = 0; wait < 15 && received.isEmpty; wait++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      alive = received.isNotEmpty;
      deliveryTime = clock.elapsed;
    }
    expect(
      alive,
      isTrue,
      reason: 'sem canal vivo, o resto deste teste não prova nada',
    );

    received.clear();
    final window = deliveryTime * 5 < const Duration(seconds: 3)
        ? const Duration(seconds: 3)
        : deliveryTime * 5;

    Object? refusal;
    try {
      await asUser(
        conn,
        uid,
        () => writeMessage(
          conn,
          authorId: uid,
          groupId: groupId,
          text: 'seu $_blocked',
        ),
      );
    } catch (e) {
      refusal = e;
    }
    expect((refusal! as ServerException).code, 'PT422');

    await Future<void>.delayed(window);

    expect(
      received,
      isEmpty,
      reason:
          'a recusa é na ESCRITA: nenhum assinante recebe evento nenhum '
          '(janela de ${window.inMilliseconds}ms, entrega medida em '
          '${deliveryTime.inMilliseconds}ms)',
    );
  }, timeout: const Timeout(Duration(seconds: 90)));
}

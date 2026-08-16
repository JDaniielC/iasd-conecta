import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — o canal de tempo real não é uma segunda
/// porta.
///
/// `notificacoes` estreou o Realtime neste projeto, e lá o canal carregava um
/// SINAL: "você tem aviso novo". Aqui ele carrega o TEXTO. O erro de
/// configuração que lá vazava a existência de um aviso, aqui vaza a conversa
/// inteira — e vaza calado, porque a tela de quem recebe demais não precisa
/// mostrar nada para o dado ter saído.
///
/// Por isso este arquivo fala com o servidor de Realtime de verdade (WebSocket
/// na 54321) e não com o Postgres na 54322 como o resto da suíte. Não dá para
/// provar o canal sem usar o canal.
///
/// Os dois lados, e o segundo é o que prova alguma coisa:
///   - quem participa RECEBE (6.2) — sem isto, "ninguém recebeu" também passaria
///     com o canal desligado;
///   - quem não participa e quem é menor de 18 NÃO recebem (6.3).
///
/// A JANELA DE ESPERA (6.4). Teste de não entrega mede ausência, e ausência
/// medida com pressa é só impaciência. A janela aqui não é um número escolhido
/// no olho: o aquecimento CRONOMETRA quanto a entrega leva de verdade nesta
/// máquina, e a espera da não entrega é 5× isso, com piso de 3 segundos. Assim
/// o teste fica honesto numa máquina lenta em vez de ficar verde por não ter
/// esperado.
///
/// Medido em 2026-08-14, Supabase local: entrega em **407 ms**, então o piso de
/// 3 s valeu — 7× a entrega observada. O piso existe justamente para o caso em
/// que o aquecimento sai rápido demais e 5× daria uma janela curta.

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

void main() {
  late Connection conn;
  late SupabaseClient clientInside, clientOutside, clientMinor;
  late String uidInside, uidOutside, uidMinor;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();

    // Sessões REAIS: o canal valida um JWT assinado, então `set
    // request.jwt.claims` no Postgres — o truque do resto da suíte — não serve.
    clientInside = SupabaseClient(_url, _publishableKey);
    clientOutside = SupabaseClient(_url, _publishableKey);
    clientMinor = SupabaseClient(_url, _publishableKey);
    uidInside = (await clientInside.auth.signInAnonymously()).session!.user.id;
    uidOutside =
        (await clientOutside.auth.signInAnonymously()).session!.user.id;
    uidMinor = (await clientMinor.auth.signInAnonymously()).session!.user.id;

    await createTestProfileWithAge(conn, uidInside, name: 'Dentro RT', age: 30);
    await createTestProfileWithAge(conn, uidOutside, name: 'Fora RT', age: 30);
    await createTestProfileWithAge(conn, uidMinor, name: 'Menor RT', age: 17);

    groupId = await createGroup(conn, ownerId: uidInside, name: 'Grupo RT');
    // A menor PARTICIPA do Grupo. É o que isola a variável: se ela não
    // recebesse por não participar, o teste não diria nada sobre idade.
    await joinGroup(conn, groupId, uidMinor);
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    for (final uid in [uidInside, uidOutside, uidMinor]) {
      await cleanUpTestUser(conn, uid);
    }
    for (final c in [clientInside, clientOutside, clientMinor]) {
      await c.dispose();
    }
    await conn.close();
  });

  test(
    'o canal entrega a quem participa e a mais ninguém',
    () async {
      final receivedInside = <String>[];
      final receivedOutside = <String>[];
      final receivedMinor = <String>[];

      Future<void> subscribeTo(
        SupabaseClient client,
        String label,
        List<String> sink,
      ) {
        final ready = Completer<void>();
        client
            .channel('chat-$label')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'mensagens',
              callback: (payload) =>
                  sink.add(payload.newRecord['texto'] as String),
            )
            .subscribe((status, _) {
              if (status == RealtimeSubscribeStatus.subscribed &&
                  !ready.isCompleted) {
                ready.complete();
              }
            });
        return ready.future;
      }

      await subscribeTo(clientInside, 'dentro', receivedInside);
      await subscribeTo(clientOutside, 'fora', receivedOutside);
      await subscribeTo(clientMinor, 'menor', receivedMinor);

      // AQUECIMENTO, e ele não é paciência com teste lento — é o que dá sentido à
      // asserção seguinte. Medido na change `notificacoes-in-app`: logo depois de
      // `supabase db reset` o servidor de Realtime ainda não pegou a publicação
      // nova e o cliente já reporta SUBSCRIBED assim mesmo. Sem aquecer, "não
      // recebeu nada" passaria também com o canal morto — o teste diria "isolado"
      // quando a verdade é "desligado".
      final clock = Stopwatch()..start();
      var deliveryTime = Duration.zero;
      var alive = false;
      for (var attempt = 0; attempt < 20 && !alive; attempt++) {
        clock.reset();
        await seedMessage(
          conn,
          authorId: uidInside,
          groupId: groupId,
          text: 'aquecimento',
        );
        for (var wait = 0; wait < 15 && receivedInside.isEmpty; wait++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        alive = receivedInside.isNotEmpty;
        deliveryTime = clock.elapsed;
      }
      expect(
        alive,
        isTrue,
        reason: 'sem canal vivo, o resto deste teste não prova nada',
      );

      receivedInside.clear();
      receivedOutside.clear();
      receivedMinor.clear();

      // A janela sai do que foi MEDIDO acima, não de um palpite.
      final window = deliveryTime * 5 < const Duration(seconds: 3)
          ? const Duration(seconds: 3)
          : deliveryTime * 5;

      await seedMessage(
        conn,
        authorId: uidInside,
        groupId: groupId,
        text: 'quem leva o som?',
      );
      await Future<void>.delayed(window);

      expect(receivedInside, [
        'quem leva o som?',
      ], reason: 'quem participa e tem 18 anos recebe o texto');
      expect(
        receivedOutside,
        isEmpty,
        reason:
            'quem não participa do Grupo não pode receber evento nenhum '
            '(janela de ${window.inMilliseconds}ms, entrega medida em '
            '${deliveryTime.inMilliseconds}ms)',
      );
      expect(
        receivedMinor,
        isEmpty,
        reason:
            'o corte de 18 anos vale NO CANAL, não só na consulta — a menor '
            'participa do Grupo e ainda assim não recebe',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

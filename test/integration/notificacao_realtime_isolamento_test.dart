import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Change `notificacoes-in-app` — o canal de tempo real não é uma segunda porta.
///
/// Esta é a **estreia do Realtime** neste projeto: até a migration desta change,
/// nenhuma tabela estava na publicação `supabase_realtime` — zero linhas em
/// `pg_publication_tables`, conferido antes de começar.
///
/// Uma tabela publicada emite evento para quem estiver inscrito, e o filtro de
/// quem recebe o quê depende de a RLS valer NO CANAL, que é um caminho de código
/// diferente do da consulta. Configurar errado transforma a inscrição num feed
/// de eventos alheios — e falha calada, porque a tela de quem recebe demais não
/// precisa mostrar nada para o dado ter saído.
///
/// Por isso este teste fala com o servidor de Realtime de verdade (WebSocket na
/// 54321), e não com o Postgres na 54322 como o resto da suíte. Não dá para
/// provar o canal sem usar o canal.
///
/// Se ele falhar, o recuo está no design: não publicar a tabela e atualizar o
/// contador por consulta ao voltar para o app. O requisito de "sobe sozinho"
/// cai; o de privacidade não.

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

void main() {
  late Connection conn;
  late SupabaseClient clienteA, clienteB;
  late String uidA, uidB;

  setUpAll(() async {
    conn = await openTestConnection();

    // Sessões REAIS: o canal valida um JWT assinado, então `set request.jwt.claims`
    // no Postgres — o truque do resto da suíte — não serve aqui.
    clienteA = SupabaseClient(_url, _publishableKey);
    clienteB = SupabaseClient(_url, _publishableKey);
    uidA = (await clienteA.auth.signInAnonymously()).session!.user.id;
    uidB = (await clienteB.auth.signInAnonymously()).session!.user.id;

    // A FK exige Perfil. `createTestProfile` já é isto — o `createTestUser`
    // interno vira no-op porque `signInAnonymously()` já criou o `auth.users`.
    await createTestProfile(conn, uidA, name: 'Pessoa A RT');
    await createTestProfile(conn, uidB, name: 'Pessoa B RT');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.notificacoes where destinatario_id = any(@u::uuid[])'),
      parameters: {'u': [uidA, uidB]},
    );
    for (final uid in [uidA, uidB]) {
      await cleanUpTestUser(conn, uid);
    }
    await clienteA.dispose();
    await clienteB.dispose();
    await conn.close();
  });

  Future<void> inserirAviso({
    required String destinatario,
    required String ator,
  }) async {
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo, ator_id) "
        "values (@d, 'convite_recebido', @a)",
      ),
      parameters: {'d': destinatario, 'a': ator},
    );
  }

  test('aviso de uma pessoa não chega no canal da outra', () async {
    final recebidosA = <String>[];
    final recebidosB = <String>[];

    Future<void> inscrever(
      SupabaseClient cliente,
      String rotulo,
      List<String> destino,
    ) {
      final pronto = Completer<void>();
      cliente
          .channel('notificacoes-$rotulo')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notificacoes',
            callback: (payload) =>
                destino.add(payload.newRecord['destinatario_id'] as String),
          )
          .subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed && !pronto.isCompleted) {
          pronto.complete();
        }
      });
      return pronto.future;
    }

    await inscrever(clienteA, 'a', recebidosA);
    await inscrever(clienteB, 'b', recebidosB);

    // AQUECIMENTO, e ele não é paciência com teste lento — é o que dá sentido à
    // asserção seguinte.
    //
    // Medido: logo depois de `supabase db reset` o servidor de Realtime ainda
    // não pegou a publicação nova, e o cliente já reporta `SUBSCRIBED` mesmo
    // assim. Sem aquecer, "B não recebeu nada" passaria também com o canal
    // morto — o teste diria "isolado" quando a verdade é "desligado", que é
    // passar pelo motivo errado.
    //
    // Então: insere para A até A receber. Só com o canal PROVADAMENTE vivo a
    // ausência em B vira evidência.
    var vivo = false;
    for (var tentativa = 0; tentativa < 20 && !vivo; tentativa++) {
      await inserirAviso(destinatario: uidA, ator: uidB);
      for (var espera = 0; espera < 10 && recebidosA.isEmpty; espera++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      vivo = recebidosA.isNotEmpty;
    }
    expect(vivo, isTrue,
        reason: 'sem canal vivo, o resto deste teste não prova nada');

    recebidosA.clear();
    recebidosB.clear();

    // Agora sim. Inserção pelo dono da tabela — o que interessa aqui é o CANAL,
    // não o gatilho. Isolar as duas coisas é o que faz este teste dizer só uma.
    await inserirAviso(destinatario: uidA, ator: uidB);

    // Janela generosa: o que se quer provar é que B NUNCA recebe, e para isso
    // vale esperar bem mais do que a entrega leva.
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(recebidosA, [uidA], reason: 'quem é dona do aviso recebe o evento');
    expect(recebidosB, isEmpty,
        reason: 'quem não é dona NÃO pode receber evento nenhum');
  }, timeout: const Timeout(Duration(seconds: 30)));
}

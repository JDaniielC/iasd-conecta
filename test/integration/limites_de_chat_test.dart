import 'package:iasd_conecta/features/chat/domain/chat_limits.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `filtro-e-intervalo-de-mensagem`, tarefas 5.2 e 5.3 — a COSTURA entre
/// o Dart e o banco.
///
/// Duas costuras, e as duas falham em silêncio se ninguém olhar:
///
///   1. **Os números.** `ChatLimits` repete o que a migration decide. Divergir
///      não produz error: a tela libera o envio antes da hora, a pessoa aperta,
///      e o servidor recusa — parecendo bug de rede.
///   2. **Os códigos.** O cliente distingue as três recusas por `errcode`, e o
///      `errcode` só chega até ele se o PostgREST o repassar. Testar isso pela
///      conexão direta com o Postgres NÃO prova nada: lá o SQLSTATE vem do
///      protocolo. É por isso que a segunda metade deste arquivo fala HTTP.


const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

/// Só na lista de conversa, e só deste arquivo.
const _blocked = 'zopilo';

void main() {
  group('5.2 — os números do Dart são os do banco', () {
    late Connection conn;

    setUpAll(() async => conn = await openTestConnection());
    tearDownAll(() => conn.close());

    Future<Object?> constantOf(String function) async {
      final r = await conn.execute('select public.$function()');
      return r.first[0];
    }

    test('intervalo mínimo', () async {
      expect(
        await constantOf('mensagem_intervalo_minimo'),
        Interval(microseconds: ChatLimits.minimumInterval.inMicroseconds),
      );
    });

    test('janela do teto', () async {
      expect(
        await constantOf('mensagem_janela_do_teto'),
        Interval(microseconds: ChatLimits.window.inMicroseconds),
      );
    });

    test('teto na janela', () async {
      expect(await constantOf('mensagem_teto_na_janela'), ChatLimits.windowCeiling);
    });

    // Change `mensagem-fixada`, tarefa 5.2 — a MESMA costura, e a divergência
    // aqui é pior: a tela ofereceria fixar quando não há vaga, e a pessoa
    // levaria PT409 depois de escolher o que fixar.
    test('teto de fixadas', () async {
      expect(
        await constantOf('mensagem_teto_de_fixadas'),
        ChatLimits.pinnedCeiling,
      );
    });
  });

  group('5.3 — a recusa chega ao cliente com o código, pela API de verdade', () {
    late Connection conn;
    late SupabaseClient client;
    late String uid;
    late String groupId;
    late String otherGroupId;
    late String floodGroupId;

    setUpAll(() async {
      conn = await openTestConnection();
      await lockBlockedWordList(conn);
      await conn.execute(
        Sql.named(
          'insert into public.palavras_bloqueadas_mensagem (palavra) '
          'values (@p) on conflict do nothing',
        ),
        parameters: {'p': _blocked},
      );

      // Sessão REAL, com JWT assinado: é o único jeito de o PostgREST entrar no
      // caminho. `set request.jwt.claims` no Postgres pula justamente a peça
      // que este grupo existe para provar.
      client = SupabaseClient(_url, _publishableKey);
      uid = (await client.auth.signInAnonymously()).session!.user.id;
      await createTestProfileWithAge(conn, uid, name: 'Autor API', age: 30);
      groupId = await createGroup(conn, ownerId: uid, name: 'Grupo API');
      otherGroupId = await createGroup(
        conn,
        ownerId: uid,
        name: 'Grupo API vizinho',
      );
      // Grupo PRÓPRIO para o caso de flood: os outros dois já carregam o
      // histórico dos casos acima — inclusive as 20 do teto —, e o teto
      // recusaria a primeira mensagem do flood pelo motivo errado.
      floodGroupId = await createGroup(
        conn,
        ownerId: uid,
        name: 'Grupo API flood',
      );
    });

    tearDownAll(() async {
      for (final g in [groupId, otherGroupId, floodGroupId]) {
        await conn.execute(
          Sql.named('delete from public.mensagens where grupo_id = @g'),
          parameters: {'g': g},
        );
        await conn.execute(
          Sql.named('delete from public.grupos where id = @g'),
          parameters: {'g': g},
        );
      }
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

    /// Escreve pela API, como o app escreve. Devolve a recusa reconhecida.
    Future<SendRefusal?> sendViaApi(String group, String text) async {
      try {
        await client.from('mensagens').insert({
          'grupo_id': group,
          'autor_id': uid,
          'texto': text,
        });
        return null;
      } on PostgrestException catch (e) {
        final refusal = SendRefusal.fromCode(e.code, e.hint);
        expect(
          refusal,
          isNotNull,
          reason: 'o error chegou sem código reconhecível: $e',
        );
        return refusal;
      }
    }

    test('palavra bloqueada chega como blockedWord, com a palavra', () async {
      final refusal = await sendViaApi(groupId, 'olha o $_blocked ali');

      expect(refusal!.kind, SendRefusalKind.blockedWord);
      expect(
        refusal.blockedWord,
        _blocked,
        reason:
            'sem a palavra a recusa não é corrigível, e a pessoa reenvia até '
            'desistir',
      );
    });

    test('intervalo chega como tooSoon, com o tempo que falta', () async {
      // Grupo próprio para não herdar a contagem do caso anterior.
      expect(await sendViaApi(otherGroupId, 'a primeira'), isNull);

      final refusal = await sendViaApi(otherGroupId, 'a segunda, colada');
      expect(refusal!.kind, SendRefusalKind.tooSoon);
      expect(refusal.retryAfter, isNotNull);
      expect(refusal.retryAfter!.inSeconds, greaterThan(0));
      expect(
        refusal.retryAfter!,
        lessThanOrEqualTo(ChatLimits.minimumInterval),
      );
    });

    test('teto chega como windowCeiling, distinto do intervalo', () async {
      // A janela se enche por trás, com histórico recuado: 20 mensagens
      // espaçadas por 10 s, todas dentro dos 5 minutos.
      for (var i = 0; i < ChatLimits.windowCeiling; i++) {
        await writeMessage(
          conn,
          authorId: uid,
          groupId: groupId,
          text: 'mensagem $i',
          createdAtOffset: Duration(
            seconds: 10 * (ChatLimits.windowCeiling - i),
          ),
        );
      }

      final refusal = await sendViaApi(groupId, 'a que passa do teto');
      expect(refusal!.kind, SendRefusalKind.windowCeiling);
      expect(
        refusal.kind,
        isNot(SendRefusalKind.tooSoon),
        reason: 'a tela precisa dizer coisas diferentes nos dois casos',
      );
      expect(refusal.retryAfter, isNotNull);
    });

    test('mandar `created_at` pela API é RECUSADO — o bypass do ritmo', () async {
      // CONVERGENCE 1, e este caso existe porque o defeito existiu. Medido em
      // 2026-08-16, antes do conserto: 30 mensagens inseridas em segundos, zero
      // recusas, bastando acrescentar `created_at` ao corpo do `insert`. O
      // gatilho de ritmo conta a janela por `created_at` das linhas existentes,
      // e linha gravada com data antiga nasce fora da janela — o limite existia
      // e não valia.
      //
      // **TEM DE RODAR PELA API.** Como `postgres` o grant de coluna não se
      // aplica (superusuário), e este caso passaria verde sobre o defeito
      // intacto. É a mesma armadilha que `security_nome_valido_rls_test`
      // documenta para RLS, aplicada a privilégio de coluna.
      Object? error;
      try {
        await client.from('mensagens').insert({
          'grupo_id': otherGroupId,
          'autor_id': uid,
          'texto': 'com data forjada',
          'created_at': '2020-01-01T00:00:00Z',
        });
      } catch (e) {
        error = e;
      }

      expect(error, isA<PostgrestException>());
      expect(
        (error! as PostgrestException).code,
        '42501',
        reason:
            'permission denied for table mensagens — a recusa é do PRIVILÉGIO '
            'de coluna, antes de qualquer policy rodar',
      );

      // E não é recusa de escrita das três desta change: a tela não deve
      // explicar palavra bloqueada nem contagem regressiva para isto.
      final e = error as PostgrestException;
      expect(SendRefusal.fromCode(e.code, e.hint), isNull);
    });

    test('o flood por data forjada não passa mais de UMA mensagem', () async {
      // O caso acima prova a recusa; este prova a CONSEQUÊNCIA. Sem ele, um
      // conserto que recusasse `created_at` mas deixasse o ritmo furado por
      // outro caminho passaria.
      var accepted = 0;
      for (var i = 0; i < 5; i++) {
        try {
          await client.from('mensagens').insert({
            'grupo_id': floodGroupId,
            'autor_id': uid,
            'texto': 'flood $i',
            if (i > 0) 'created_at': '2020-01-01T00:00:00Z',
          });
          accepted++;
        } catch (_) {
          // Recusada, que é o esperado da segunda em diante.
        }
      }

      expect(
        accepted,
        1,
        reason:
            'a primeira passa; as outras quatro caem — a de data forjada por '
            'privilégio, e as demais pelo intervalo de 3 s. Medido em 30 antes '
            'do conserto',
      );
    });

    test('error que não é recusa de escrita não vira SendRefusal', () async {
      // O contraste. Sem ele, um `fromError` que devolvesse sempre a mesma
      // recusa passaria em tudo acima — e a tela explicaria palavra bloqueada
      // para uma queda de rede.
      Object? other;
      try {
        await client.from('mensagens').insert({
          'grupo_id': groupId,
          // Assinar por outra pessoa: a policy recusa, e é recusa de OUTRA
          // natureza.
          'autor_id': '00000000-0000-0000-0000-0000000000ff',
          'texto': 'nao sou eu',
        });
      } catch (e) {
        other = e;
      }
      expect(other, isA<PostgrestException>());
      final e = other! as PostgrestException;
      expect(SendRefusal.fromCode(e.code, e.hint), isNull);
    });
  });
}

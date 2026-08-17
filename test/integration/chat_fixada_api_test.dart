import 'package:iasd_conecta/features/chat/domain/chat_limits.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal.dart';
import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `mensagem-fixada`, tarefa 5.3 — a fixação pela API DE VERDADE.
///
/// Este arquivo fala HTTP, e não `set request.jwt.claims`, porque duas peças
/// desta change só existem no caminho do PostgREST:
///
///   1. **O `errcode` PT409.** A tela distingue "não pode fixar" de "não cabe
///      mais" pelo código, nunca pelo texto — e o código só chega se o
///      PostgREST o repassar. Pela conexão direta o SQLSTATE vem do protocolo e
///      não prova nada.
///   2. **A fixada ANTIGA, fora da primeira página do histórico.** É o caso que
///      dá sentido à faixa: o que se fixa é justamente o que ia afundar. Uma
///      consulta que só olhasse a página traria a faixa vazia.
///
/// As chamadas repetem o que `ChatRepository` faz — mesmas colunas, mesma
/// ordem, mesmos filtros. `ChatRepository` em si arrasta `supabase_flutter` e
/// com ele o Flutter inteiro, que não roda em `dart test`; o que se prova aqui
/// é o contrato do banco que ele consome.

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

/// O tamanho de página de `_pageSize`, repetido aqui porque
/// aquele arquivo importa `supabase_flutter` e arrasta o Flutter inteiro, que
/// não roda em `dart test`. A cópia não fica solta: a asserção deste arquivo é
/// que a fixada NÃO está na página, e ela falha alto se os dois divergirem.
const _pageSize = 50;

void main() {
  late Connection conn;
  late SupabaseClient client;
  late String uid;
  late String groupId;

  /// Fixa pela API, como `ChatRepository.pinMessage`. Devolve a recusa
  /// reconhecida, ou nulo quando passou.
  Future<SendRefusal?> pinViaApi(String messageId) async {
    try {
      final rows = await client
          .from('mensagens')
          .update({
            'fixada_em': DateTime.now().toUtc().toIso8601String(),
            'fixada_por': uid,
          })
          .eq('id', messageId)
          .select();
      expect(
        rows,
        isNotEmpty,
        reason: 'zero linha é a OUTRA recusa — a policy, não o gatilho',
      );
      return null;
    } on PostgrestException catch (e) {
      final refusal = SendRefusal.fromCode(e.code, e.hint);
      expect(refusal, isNotNull, reason: 'error sem código reconhecível: $e');
      return refusal;
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    // Sessão REAL, com JWT assinado.
    client = SupabaseClient(_url, _publishableKey);
    uid = (await client.auth.signInAnonymously()).session!.user.id;
    await createTestProfileWithAge(conn, uid, name: 'Dona FD', age: 30);
    groupId = await createGroup(conn, ownerId: uid, name: 'Grupo FD');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, uid);
    await client.dispose();
    await conn.close();
  });

  setUp(() async {
    await conn.execute(
      Sql.named('delete from public.mensagens where grupo_id = @g'),
      parameters: {'g': groupId},
    );
  });

  test('fixar e desfixar pela API, com quem fixou gravado', () async {
    final id = await seedMessage(
      conn,
      authorId: uid,
      groupId: groupId,
      text: 'o ponto de encontro mudou',
    );

    expect(await pinViaApi(id), isNull);
    final pinned = await pinnedStateOf(conn, id);
    expect(pinned.pinned, isTrue);
    expect(pinned.pinnedBy, uid);

    final unpinned = await client
        .from('mensagens')
        .update({'fixada_em': null, 'fixada_por': null})
        .eq('id', id)
        .select();
    expect(unpinned, hasLength(1));
    expect((await pinnedStateOf(conn, id)).pinned, isFalse);
  });

  test('o teto chega como pinnedCeiling, com o número', () async {
    for (var i = 0; i < ChatLimits.pinnedCeiling; i++) {
      final id = await seedMessage(
        conn,
        authorId: uid,
        groupId: groupId,
        text: 'fixada $i',
      );
      expect(await pinViaApi(id), isNull);
    }

    final extra = await seedMessage(
      conn,
      authorId: uid,
      groupId: groupId,
      text: 'a que não cabe',
    );
    final refusal = await pinViaApi(extra);

    expect(refusal!.kind, SendRefusalKind.pinnedCeiling);
    expect(
      refusal.ceiling,
      ChatLimits.pinnedCeiling,
      reason: 'o número vem do banco, e a tela não precisa confiar na cópia',
    );
  });

  test('a fixada ANTIGA vem, mesmo fora da primeira página do histórico',
      () async {
    // A mais antiga de todas, e depois uma página inteira de conversa por cima.
    final oldest = await seedMessage(
      conn,
      authorId: uid,
      groupId: groupId,
      text: 'o endereço, combinado lá atrás',
    );
    for (var i = 0; i < _pageSize; i++) {
      await seedMessage(
        conn,
        authorId: uid,
        groupId: groupId,
        text: 'bate-papo $i',
      );
    }
    expect(await pinViaApi(oldest), isNull);

    // O histórico, como `ChatRepository.fetchHistory` o pede.
    final page = await client
        .from('mensagens')
        .select()
        .eq('grupo_id', groupId)
        .order('created_at', ascending: false)
        .limit(_pageSize);
    expect(
      page.map((r) => r['id']),
      isNot(contains(oldest)),
      reason: 'sem isto o caso não é o que ele diz ser',
    );

    // A segunda consulta, como `ChatRepository.fetchPinned` a pede.
    final pinned = await client
        .from('mensagens')
        .select()
        .eq('grupo_id', groupId)
        .not('fixada_em', 'is', null)
        .order('fixada_em', ascending: false);

    expect(pinned, hasLength(1));
    final message = Message.fromMap(pinned.single);
    expect(message.id, oldest);
    expect(message.isPinned, isTrue);
    expect(message.pinnedBy, uid);
    expect(message.tombstone, MessageTombstone.visible);
  });

  test('lápide nunca sai na consulta das fixadas', () async {
    final id = await seedMessage(
      conn,
      authorId: uid,
      groupId: groupId,
      text: 'fixada e depois removida',
    );
    expect(await pinViaApi(id), isNull);

    await client
        .from('mensagens')
        .update({
          'texto': null,
          'removida_em': DateTime.now().toUtc().toIso8601String(),
          'removida_por': uid,
        })
        .eq('id', id)
        .select();

    final pinned = await client
        .from('mensagens')
        .select()
        .eq('grupo_id', groupId)
        .not('fixada_em', 'is', null);
    expect(
      pinned,
      isEmpty,
      reason: 'o gatilho desfixa a lápide, e ela não ocupa vaga nem faixa',
    );
  });
}

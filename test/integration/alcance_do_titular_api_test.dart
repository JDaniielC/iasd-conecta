import 'package:postgres/postgres.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `alcance-do-titular-sobre-texto-proprio`, Convergência 1 — as duas
/// funções pela API DE VERDADE.
///
/// `test/integration/alcance_do_titular_test.dart` já prova o CONTRATO das
/// duas funções por conexão direta (`conn.execute`), e
/// `test/widget/pinned_messages_section_test.dart` já prova a TELA contra um
/// `ChatRepository` mockado. O que nenhum dos dois prova é que
/// `ChatRepository.unpinMyMessage`/`fetchMyPinned` — que chamam
/// `_client.rpc('desfixar_minha_mensagem', params: {'p_mensagem_id': ...})` e
/// `_client.rpc('minhas_mensagens_fixadas')` — alcançam o PostgREST de
/// verdade com esse nome de função e esse nome de parâmetro. Um erro de
/// digitação num dos dois só aparece no caminho HTTP real, o mesmo raciocínio
/// de `chat_fixada_api_test.dart`.
const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

void main() {
  late Connection conn;
  late SupabaseClient authorClient;
  late SupabaseClient otherClient;
  late String authorUid;
  late String otherUid;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    authorClient = SupabaseClient(_url, _publishableKey);
    otherClient = SupabaseClient(_url, _publishableKey);
    authorUid = (await authorClient.auth.signInAnonymously()).session!.user.id;
    otherUid = (await otherClient.auth.signInAnonymously()).session!.user.id;
    await createTestProfileWithAge(conn, authorUid, name: 'Autora API', age: 30);
    await createTestProfileWithAge(conn, otherUid, name: 'Outra API', age: 30);
    // A autora é dona do próprio Grupo: alcançar de fora da conversa é o que
    // já está provado por conexão direta. Aqui o que importa é o caminho
    // HTTP, não recriar o cenário de "saiu do Grupo".
    groupId = await createGroup(conn, ownerId: authorUid, name: 'Grupo API FD');
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, authorUid);
    await cleanUpTestUser(conn, otherUid);
    await authorClient.dispose();
    await otherClient.dispose();
    await conn.close();
  });

  test('desfixar_minha_mensagem pela API: desfixa a própria, zero na alheia',
      () async {
    final id = await seedMessage(
      conn,
      authorId: authorUid,
      groupId: groupId,
      text: 'combinado, chego às 8 (api)',
    );
    await asUser(
      conn,
      authorUid,
      () => pinMessage(conn, uid: authorUid, messageId: id),
    );

    // Quem não é autor: zero, exatamente como na conexão direta.
    final zero = await otherClient.rpc(
      'desfixar_minha_mensagem',
      params: {'p_mensagem_id': id},
    );
    expect(zero, 0);
    expect((await pinnedStateOf(conn, id)).pinned, isTrue);

    // O autor, pela API real — o mesmo caminho que ChatRepository.unpinMyMessage usa.
    final linhas = await authorClient.rpc(
      'desfixar_minha_mensagem',
      params: {'p_mensagem_id': id},
    );
    expect(linhas, 1);
    expect((await pinnedStateOf(conn, id)).pinned, isFalse);
  });

  test('minhas_mensagens_fixadas pela API: só a própria, sem fixada_por',
      () async {
    final mine = await seedMessage(
      conn,
      authorId: authorUid,
      groupId: groupId,
      text: 'minha fixada (api)',
    );
    final theirs = await seedMessage(
      conn,
      authorId: otherUid,
      groupId: groupId,
      text: 'fixada de outra pessoa (api)',
    );
    await asUser(
      conn,
      authorUid,
      () => pinMessage(conn, uid: authorUid, messageId: mine),
    );
    await asUser(
      conn,
      authorUid,
      () => pinMessage(conn, uid: authorUid, messageId: theirs),
    );

    final rows = await authorClient.rpc('minhas_mensagens_fixadas')
        as List<dynamic>;

    expect(rows, hasLength(1));
    final row = rows.single as Map<String, dynamic>;
    expect(row['id'], mine);
    expect(row['nome_espaco'], 'Grupo API FD');
    expect(
      row.containsKey('fixada_por'),
      isFalse,
      reason: 'a função não devolve essa coluna — dado sobre outra pessoa',
    );
  });
}

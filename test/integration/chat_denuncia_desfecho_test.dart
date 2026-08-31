import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — remover a mensagem RESOLVE a denúncia, na
/// mesma transação.
///
/// Convergência 2. A tela fazia duas escritas: `removeMessage()` e depois
/// `resolveReport(mensagem_removida)`. Não era transação, e nada reparava o
/// meio do caminho — medido: mensagem sem texto, denúncia `pendente`,
/// `resolvida_em` nulo, nenhum gatilho consertando.
///
/// O estado sujo não era o pior. O botão da tela só aparece enquanto a mensagem
/// não foi removida, então a denúncia presa nesse meio ficava `pendente` PARA
/// SEMPRE, sem nenhum botão que a resolvesse — violando "toda denúncia DEVE
/// terminar em um de dois estados".
///
/// O conserto não é transação na tela: é gatilho. A spec já dizia "WHEN quem
/// tem autoridade remove a mensagem denunciada THEN a denúncia passa a mensagem
/// removida" — isso é uma consequência da remoção, não um segundo pedido do
/// cliente. Como gatilho, vale também para quem remove pela tela da CONVERSA,
/// que nunca soube que havia denúncia.

const _uidOwner = '19000000-0000-0000-0000-000000000001';
const _uidMember = '19000000-0000-0000-0000-000000000002';
const _allUids = [_uidOwner, _uidMember];

void main() {
  late Connection conn;
  late String groupId;

  Future<({String state, bool resolved})> reportOf(String reportId) async {
    final r = await conn.execute(
      Sql.named(
        'select estado, resolvida_em from public.denuncias_mensagem '
        'where id = @d',
      ),
      parameters: {'d': reportId},
    );
    final row = r.single.toColumnMap();
    return (
      state: row['estado']! as String,
      resolved: row['resolvida_em'] != null,
    );
  }

  Future<String> reportOn(String messageId, {String reason = 'motivo'}) async {
    final r = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d) '
        'returning id',
      ),
      parameters: {'m': messageId, 'mo': reason, 'd': _uidMember},
    );
    return r.single.toColumnMap()['id']! as String;
  }

  Future<void> removeAs(String uid, String messageId) =>
      asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'update public.mensagens set texto = null, removida_em = now(), '
            'removida_por = @u where id = @m',
          ),
          parameters: {'m': messageId, 'u': uid},
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo D2');
    await joinGroup(conn, groupId, _uidMember);
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    'remover a mensagem dá desfecho à denúncia pendente sobre ela',
    () async {
      final m = await seedMessage(
        conn,
        authorId: _uidMember,
        groupId: groupId,
        text: 'algo denunciado',
      );
      final reportId = await reportOn(m);
      expect((await reportOf(reportId)).state, 'pendente');

      await removeAs(_uidOwner, m);

      final after = await reportOf(reportId);
      expect(after.state, 'mensagem_removida');
      expect(after.resolved, isTrue);
    },
  );

  test('vale também para quem remove pela tela da CONVERSA, sem saber da '
      'denúncia', () async {
    // É a razão de ser gatilho e não duas chamadas do cliente: a tela de
    // conversa não consulta denúncia nenhuma, e mesmo assim a remoção feita por
    // ali não pode deixar caso pendurado.
    final m = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'removida pela conversa',
    );
    final reportId = await reportOn(m, reason: 'motivo da conversa');

    // O próprio autor removendo — caminho que nunca passa pela tela de
    // denúncias.
    await removeAs(_uidMember, m);

    expect((await reportOf(reportId)).state, 'mensagem_removida');
  });

  test('denúncia JÁ resolvida não é reescrita pela remoção', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'julgada antes',
    );
    final reportId = await reportOn(m, reason: 'julgada antes de remover');
    await conn.execute(
      Sql.named(
        "update public.denuncias_mensagem set estado = 'improcedente', "
        'resolvida_em = now() where id = @d',
      ),
      parameters: {'d': reportId},
    );

    await removeAs(_uidOwner, m);

    expect(
      (await reportOf(reportId)).state,
      'improcedente',
      reason: 'o gatilho só alcança quem estava pendente',
    );
  });

  test('remover de novo não reabre nem redecide nada', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'removida duas vezes',
    );
    final reportId = await reportOn(m, reason: 'duas remoções');
    await removeAs(_uidOwner, m);
    final first = await reportOf(reportId);

    await removeAs(_uidOwner, m);

    expect((await reportOf(reportId)).state, first.state);
  });
}

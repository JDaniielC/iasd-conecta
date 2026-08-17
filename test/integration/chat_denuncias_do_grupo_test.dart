import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — a lista de denúncias do Dono do Grupo
/// alcança as Ações daquele Grupo.
///
/// Convergência 1. A spec diz, com todas as letras: o Dono "vê as do chat do
/// Grupo dele **e as dos chats das Ações daquele Grupo**". A RLS sempre
/// permitiu — `pode_moderar_espaco` tem o braço do Dono do Grupo da Ação. Quem
/// não permitia era a CONSULTA do app, que filtrava por `mensagens.grupo_id`;
/// denúncia de chat de Ação tem esse campo nulo e sumia da tela, sem nada
/// indicar que faltava alguma coisa.
///
/// Por isso a consulta virou função no banco: repetir a regra de "o que
/// pertence a este espaço" no PostgREST e na policy são duas cópias, e a
/// primeira divergência entre elas é esta — uma tela mostrando menos do que a
/// pessoa tem direito de ver.

// PREFIXO PRÓPRIO, e a troca é conserto e não arrumação. Este arquivo usava
// `c4000000`, os mesmos TRÊS uids de `convite_nao_reserva_vaga_test.dart` —
// medido em 2026-08-17: `dart test test/integration` falhava de forma
// intermitente no `tearDownAll` daquele arquivo, porque os dois apagam os
// mesmos `perfis` em paralelo e quem chega depois encontra a linha já sem
// existir ou ainda referenciada. É o caso concreto da dívida `PENDENCIAS.md`
// 2.21, e `cc000000` foi conferido como livre em toda a suíte.
const _uidOwner = 'cc000000-0000-0000-0000-000000000001';
const _uidMember = 'cc000000-0000-0000-0000-000000000002';
const _uidOtherOwner = 'cc000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidMember, _uidOtherOwner];

void main() {
  late Connection conn;
  late String groupId, otherGroup, roundId, groupActionId;

  Future<List<String>> reasonsSeenBy(
    String uid, {
    String? group,
    String? action,
  }) => asUser(conn, uid, () async {
    final r = await conn.execute(
      Sql.named(
        'select motivo from public.denuncias_do_espaco(@g, @a) '
        'order by motivo',
      ),
      parameters: {'g': group, 'a': action},
    );
    return [for (final row in r) row.toColumnMap()['motivo']! as String];
  });

  Future<void> report(String messageId, String reason) async {
    await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
      ),
      parameters: {'m': messageId, 'mo': reason, 'd': _uidMember},
    );
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo C4');
    await joinGroup(conn, groupId, _uidMember);
    otherGroup = await createGroup(
      conn,
      ownerId: _uidOtherOwner,
      name: 'Outro C4',
    );

    roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidOwner,
    );
    groupActionId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      name: 'Ação do Grupo C4',
    );
    await makeWinner(conn, roundId, groupActionId);

    final groupMessage = await seedMessage(
      conn,
      authorId: _uidMember,
      groupId: groupId,
      text: 'no chat do Grupo',
    );
    final actionMessage = await seedMessage(
      conn,
      authorId: _uidMember,
      actionId: groupActionId,
      text: 'no chat da Ação',
    );
    await report(groupMessage, 'denuncia do chat do GRUPO');
    await report(actionMessage, 'denuncia do chat da ACAO');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.denuncias_mensagem where mensagem_id in '
        '(select id from public.mensagens where grupo_id = @g or acao_id = @a)',
      ),
      parameters: {'g': groupId, 'a': groupActionId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where grupo_id = @g or acao_id = @a',
      ),
      parameters: {'g': groupId, 'a': groupActionId},
    );
    await conn.execute(
      Sql.named(
        'update public.rodadas_votacao set vencedora_id = null where id = @r',
      ),
      parameters: {'r': roundId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': groupActionId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where id = @r'),
      parameters: {'r': roundId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = any(@gs::uuid[])'),
      parameters: {
        'gs': [groupId, otherGroup],
      },
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    'o Dono vê as denúncias do Grupo E as das Ações daquele Grupo',
    () async {
      expect(await reasonsSeenBy(_uidOwner, group: groupId), [
        'denuncia do chat da ACAO',
        'denuncia do chat do GRUPO',
      ]);
    },
  );

  test('pedindo pelo espaço da Ação, vem só a daquela Ação', () async {
    expect(await reasonsSeenBy(_uidOwner, action: groupActionId), [
      'denuncia do chat da ACAO',
    ]);
  });

  test(
    'participante comum não vê nenhuma, nem a que ele mesmo registrou',
    () async {
      expect(await reasonsSeenBy(_uidMember, group: groupId), isEmpty);
    },
  );

  test('o Dono de OUTRO Grupo não vê nada deste', () async {
    expect(await reasonsSeenBy(_uidOtherOwner, group: groupId), isEmpty);
  });
}

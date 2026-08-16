import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — excluir a conta alcança o TEXTO.
///
/// Mudança de comportamento em relação ao que a exclusão fazia antes: até aqui
/// ela anonimizava o Perfil e conservava tudo o mais do titular. Anonimizar o
/// Perfil não anonimiza um nome escrito DENTRO de um texto, e o texto é do
/// titular — some com ele.
///
/// Some o texto, fica a LÁPIDE, e a lápide não é a mesma da moderação:
///   texto nulo + `removida_em` NULO  -> "mensagem de conta excluída"
///   texto nulo + `removida_em` cheio -> "mensagem removida"
/// São fatos diferentes e quem lê merece saber qual foi. Por isso o teste não
/// se contenta com "o texto sumiu": ele olha `removida_em` nos dois casos, e
/// prova que uma mensagem já removida por moderação NÃO perde essa marca ao o
/// autor excluir a conta depois.
///
/// LIMITE DECLARADO, e ele está na Política de Privacidade: mensagem de
/// TERCEIRO que cite a pessoa não é apagada por aqui. Aquilo é texto de outra
/// pessoa, e sai por denúncia, não por exclusão de conta.

const _uidOwner = 'b2000000-0000-0000-0000-000000000001';
const _uidSubject = 'b2000000-0000-0000-0000-000000000002';
const _uidOther = 'b2000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidSubject, _uidOther];

void main() {
  late Connection conn;
  late String groupId;
  late String subjectMessage, thirdPartyMessage, alreadyRemovedMessage;

  Future<({bool hasText, bool removed})> state(String id) =>
      messageStateOf(conn, id);

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
    // O titular NÃO é dono do Grupo nem Administrador de propósito: com herança
    // a excluir_minha_conta exige herdeiro, e este arquivo estaria testando
    // aquela regra em vez desta.
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo B2');
    for (final uid in [_uidSubject, _uidOther]) {
      await joinGroup(conn, groupId, uid);
    }

    subjectMessage = await seedMessage(
      conn,
      authorId: _uidSubject,
      groupId: groupId,
      text: 'sou a Fulana e meu telefone é 99999-9999',
    );
    thirdPartyMessage = await seedMessage(
      conn,
      authorId: _uidOther,
      groupId: groupId,
      text: 'a Fulana leva o som',
    );
    alreadyRemovedMessage = await seedMessage(
      conn,
      authorId: _uidSubject,
      groupId: groupId,
      text: 'algo já moderado',
    );
    await conn.execute(
      Sql.named(
        'update public.mensagens set texto = null, '
        'removida_em = now(), removida_por = @u where id = @m',
      ),
      parameters: {'m': alreadyRemovedMessage, 'u': _uidOwner},
    );

    await asUser(
      conn,
      _uidSubject,
      () => conn.execute('select public.excluir_minha_conta()'),
    );
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
    'o Perfil do titular foi mesmo anonimizado — sem isso nada abaixo vale',
    () async {
      final r = await conn.execute(
        Sql.named(
          'select anonimizado_em, idade from public.perfis where id = @u',
        ),
        parameters: {'u': _uidSubject},
      );
      final row = r.single.toColumnMap();
      expect(row['anonimizado_em'], isNotNull);
      expect(row['idade'], isNull);
    },
  );

  test('a mensagem do titular perde o texto e fica com a lápide de conta '
      'excluída', () async {
    final e = await state(subjectMessage);
    expect(e.hasText, isFalse);
    expect(
      e.removed,
      isFalse,
      reason:
          'removida_em nulo é o que faz a tela dizer "mensagem de conta '
          'excluída" e não "mensagem removida"',
    );
  });

  test('mensagem de TERCEIRO que cite a pessoa fica intacta', () async {
    final e = await state(thirdPartyMessage);
    expect(
      e.hasText,
      isTrue,
      reason:
          'texto de outra pessoa sai por denúncia, não por exclusão de '
          'conta — é o limite declarado na Política',
    );
  });

  test(
    'mensagem já removida por moderação mantém a marca da moderação',
    () async {
      final e = await state(alreadyRemovedMessage);
      expect(e.hasText, isFalse);
      expect(
        e.removed,
        isTrue,
        reason:
            'as duas lápides são fatos diferentes; a exclusão de conta não '
            'apaga o registro de que houve moderação',
      );
      final r = await conn.execute(
        Sql.named(
          'select removida_por::text from public.mensagens where id = @m',
        ),
        parameters: {'m': alreadyRemovedMessage},
      );
      expect(r.single.toColumnMap()['removida_por'], _uidOwner);
    },
  );

  test(
    'a linha da mensagem continua existindo — some o texto, não o rastro',
    () async {
      final r = await conn.execute(
        Sql.named('select count(*) from public.mensagens where grupo_id = @g'),
        parameters: {'g': groupId},
      );
      expect(
        r.first[0],
        3,
        reason:
            'o rastro de que existiu mensagem ali é o que mantém a conversa '
            'legível para quem ficou',
      );
    },
  );
}

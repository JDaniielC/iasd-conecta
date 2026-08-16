import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — quem lê o chat de um Grupo.
///
/// O caso que mais importa é o de quem SAIU: ele deixa de ler inclusive as
/// mensagens anteriores à saída. Não é retroatividade — é que o predicado
/// pergunta pela participação de AGORA, e a conversa é do espaço, não da
/// pessoa. Guardar "podia ler até tal data" exigiria versionar participação.
///
/// Grupo arquivado é o oposto e por isso está aqui junto: a escrita fecha, a
/// leitura continua. O histórico é justamente o que sobra de um Grupo
/// arquivado.

const _uidOwner = 'ac000000-0000-0000-0000-000000000001';
const _uidMember = 'ac000000-0000-0000-0000-000000000002';
const _uidLeaver = 'ac000000-0000-0000-0000-000000000003';
const _uidOutsider = 'ac000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidMember, _uidLeaver, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId, archived, leaverMessage;

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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo AC');
    await joinGroup(conn, groupId, _uidMember);
    await joinGroup(conn, groupId, _uidLeaver);
    await seedMessage(conn, authorId: _uidOwner, groupId: groupId);
    // Escrita por quem vai sair, para a segunda metade do cenário ter o que
    // conferir: sair leva embora o acesso, não o que já foi dito.
    leaverMessage = await seedMessage(
      conn,
      authorId: _uidLeaver,
      groupId: groupId,
      text: 'combinei antes de sair',
    );

    archived = await createGroup(
      conn,
      ownerId: _uidOwner,
      name: 'Grupo AC velho',
    );
    await seedMessage(conn, authorId: _uidOwner, groupId: archived);
    await conn.execute(
      Sql.named('update public.grupos set arquivado_em = now() where id = @g'),
      parameters: {'g': archived},
    );
  });

  tearDownAll(() async {
    for (final g in [groupId, archived]) {
      await clearGroupChat(conn, g);
      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': g},
      );
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('participante lê e escreve', () async {
    expect(
      await asUser(
        conn,
        _uidMember,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      greaterThan(0),
    );
    final id = await asUser(
      conn,
      _uidMember,
      () => writeMessage(conn, authorId: _uidMember, groupId: groupId),
    );
    expect(id, isNotEmpty);
  });

  test('quem não participa lê 0', () async {
    expect(
      await asUser(
        conn,
        _uidOutsider,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
    );
  });

  test('quem sai deixa de ler INCLUSIVE o que era anterior à saída', () async {
    expect(
      await asUser(
        conn,
        _uidLeaver,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      greaterThan(0),
      reason: 'enquanto participa, lê',
    );

    await asUser(conn, _uidLeaver, () async {
      await conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo '
          'where grupo_id = @g and usuario_id = @u',
        ),
        parameters: {'g': groupId, 'u': _uidLeaver},
      );
    });

    expect(
      await asUser(
        conn,
        _uidLeaver,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
      reason: 'o predicado pergunta pela participação de agora',
    );

    // A SEGUNDA METADE DO CENÁRIO, e ela é o que protege contra o conserto
    // errado. A spec diz "AND as mensagens que ela escreveu continuam visíveis
    // para quem ficou": sem esta asserção, alguém apertando a policy para
    // resolver a primeira metade apagaria a conversa de quem permaneceu, e nada
    // ficaria vermelho. Sair leva embora o ACESSO, não o que já foi dito.
    expect(
      await asUser(
        conn,
        _uidOwner,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      greaterThan(0),
      reason: 'quem ficou continua lendo a conversa inteira',
    );
    expect(
      (await messageStateOf(conn, leaverMessage)).hasText,
      isTrue,
      reason: 'o texto de quem saiu fica — sair não é excluir a conta',
    );
  });

  test('Grupo arquivado: leitura continua, escrita fecha', () async {
    expect(
      await asUser(
        conn,
        _uidOwner,
        () => visibleMessageCount(conn, groupId: archived),
      ),
      greaterThan(0),
      reason: 'o histórico é o que sobra de um Grupo arquivado',
    );

    Object? error;
    try {
      await asUser(
        conn,
        _uidOwner,
        () => writeMessage(conn, authorId: _uidOwner, groupId: archived),
      );
    } catch (e) {
      error = e;
    }
    expect(error, isA<ServerException>());
  });
}

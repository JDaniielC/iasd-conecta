import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — quem remove, e o que sobra depois.
///
/// Seis papéis, e a linha divisória não é "quem lê": o Administrador do distrito
/// REMOVE sem poder LER o chat inteiro, e o dono de outro Grupo não faz nem uma
/// coisa nem outra. Moderar é autoridade sobre o espaço; ler é pertencer a ele.
///
/// Depois de remover, o texto some para TODOS — inclusive para quem removeu e
/// para o Administrador. O texto removido não é guardado em lugar nenhum:
/// conservá-lo recriaria dentro do banco justamente o dado que a remoção existe
/// para eliminar, e num lugar com menos gente olhando. Quem remove lê antes,
/// porque depois não dá para reconsiderar.

const _uidOwner = 'af000000-0000-0000-0000-000000000001';
const _uidAuthor = 'af000000-0000-0000-0000-000000000002';
const _uidMember = 'af000000-0000-0000-0000-000000000003';
const _uidAdmin = 'af000000-0000-0000-0000-000000000004';
const _uidOtherGroupOwner = 'af000000-0000-0000-0000-000000000005';
const _allUids = [
  _uidOwner,
  _uidAuthor,
  _uidMember,
  _uidAdmin,
  _uidOtherGroupOwner,
];

void main() {
  late Connection conn;
  late String groupId, otherGroup, looseActionId;

  Future<Object?> removeAs(String uid, String messageId) async {
    try {
      await asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'update public.mensagens set texto = null, '
            'removida_em = now(), removida_por = @u where id = @m',
          ),
          parameters: {'m': messageId, 'u': uid},
        );
      });
      return null;
    } catch (e) {
      return e;
    }
  }

  Future<int> rowsAffectedBy(String uid, String messageId) =>
      asUser(conn, uid, () async {
        final r = await conn.execute(
          Sql.named(
            'update public.mensagens set texto = null, '
            'removida_em = now(), removida_por = @u where id = @m',
          ),
          parameters: {'m': messageId, 'u': uid},
        );
        return r.affectedRows;
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
    await createTestDistrictAdmin(conn, _uidAdmin);
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo AF');
    for (final uid in [_uidAuthor, _uidMember]) {
      await joinGroup(conn, groupId, uid);
    }
    otherGroup = await createGroup(
      conn,
      ownerId: _uidOtherGroupOwner,
      name: 'Outro AF',
    );
    looseActionId = await createLooseAction(
      conn,
      creatorId: _uidAuthor,
      name: 'Ação avulsa AF',
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.denuncias_mensagem where mensagem_id in '
        '(select id from public.mensagens where grupo_id = any(@gs::uuid[]))',
      ),
      parameters: {
        'gs': [groupId, otherGroup],
      },
    );
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where grupo_id = any(@gs::uuid[])',
      ),
      parameters: {
        'gs': [groupId, otherGroup],
      },
    );
    await conn.execute(
      Sql.named('delete from public.mensagens where acao_id = @a'),
      parameters: {'a': looseActionId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': looseActionId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@us::uuid[])'),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _uidAdmin},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('os quatro que podem remover conseguem', () async {
    for (final (role, uid) in [
      ('a própria autora', _uidAuthor),
      ('a dona do Grupo', _uidOwner),
      ('o Administrador do distrito', _uidAdmin),
    ]) {
      final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
      expect(await removeAs(uid, m), isNull, reason: role);
      expect((await messageStateOf(conn, m)).hasText, isFalse, reason: role);
      expect((await messageStateOf(conn, m)).removed, isTrue, reason: role);
    }
  });

  test('participante comum e dona de OUTRO Grupo não removem', () async {
    for (final (role, uid) in [
      ('participante comum', _uidMember),
      ('dona de outro Grupo', _uidOtherGroupOwner),
    ]) {
      final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
      // Recusa por RLS de update é ZERO LINHA, não erro.
      expect(await rowsAffectedBy(uid, m), 0, reason: role);
      expect((await messageStateOf(conn, m)).hasText, isTrue, reason: role);
    }
  });

  test(
    'depois de removida, o texto some para TODOS — inclusive quem removeu',
    () async {
      final m = await seedMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
        text: 'algo que não devia ter sido dito',
      );
      await removeAs(_uidOwner, m);

      for (final uid in [_uidOwner, _uidAuthor, _uidMember, _uidAdmin]) {
        final r = await asUser(conn, uid, () async {
          final x = await conn.execute(
            Sql.named('select texto from public.mensagens where id = @m'),
            parameters: {'m': m},
          );
          return x.isEmpty ? 'invisível' : x.single.toColumnMap()['texto'];
        });
        expect(r, anyOf(isNull, 'invisível'), reason: uid);
      }
    },
  );

  test('remover de novo não sobrescreve quem removeu primeiro', () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    await removeAs(_uidOwner, m);
    final first = await conn.execute(
      Sql.named(
        'select removida_por::text, removida_em from public.mensagens where id = @m',
      ),
      parameters: {'m': m},
    );
    final who = first.single.toColumnMap()['removida_por'];

    await removeAs(_uidAdmin, m);
    final after = await conn.execute(
      Sql.named(
        'select removida_por::text from public.mensagens where id = @m',
      ),
      parameters: {'m': m},
    );
    expect(
      after.single.toColumnMap()['removida_por'],
      who,
      reason: 'o registro é de quem removeu, e isso aconteceu uma vez',
    );
  });

  // O BURACO QUE ESTE TESTE FECHA: até 2026-08-14 toda a moderação era provada
  // em chat de GRUPO, e `pode_ver_chat_grupo` tem o braço de Administrador
  // enquanto `pode_ver_chat_acao` não tinha. O comentário da própria função
  // afirmava que tinha. Resultado: o Administrador do distrito não alcançava a
  // linha numa Ação, o `update` afetava ZERO linha, e a tela do moderador dizia
  // que deu certo. Achado pelo agente `advogado-digital` ao conferir a
  // Política contra o código — não pela suíte, que só olhava Grupo.
  test('o Administrador do distrito também remove em chat de AÇÃO', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidAuthor,
      actionId: looseActionId,
    );
    expect(
      await rowsAffectedBy(_uidAdmin, m),
      1,
      reason: 'remover exige ALCANÇAR a linha, e alcançar é ler',
    );
    expect((await messageStateOf(conn, m)).hasText, isFalse);
  });

  test('quem não tem nada com a Ação não remove dela', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidAuthor,
      actionId: looseActionId,
    );
    expect(await rowsAffectedBy(_uidOtherGroupOwner, m), 0);
    expect((await messageStateOf(conn, m)).hasText, isTrue);
  });
}

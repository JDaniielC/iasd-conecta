import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — o que o banco aceita como escrita.
///
/// Duas barreiras diferentes, e o teste separa: o LIMITE de 2000 e o texto vazio
/// caem por `check` de constraint; assinar por outro cai por policy. E a
/// não-edição cai por gatilho, que é a terceira — a policy de update diz QUEM,
/// não O QUÊ, e sem o gatilho quem pode remover conseguiria reescrever.
///
/// 2000 é escolha, não medição: é conversa de combinação, não redação. O teste
/// fixa a fronteira nos dois lados porque um `between` errado por um é o tipo de
/// defeito que só aparece no dia em que alguém escreve muito.

const _uidOwner = 'ae000000-0000-0000-0000-000000000001';
const _uidOther = 'ae000000-0000-0000-0000-000000000002';
const _allUids = [_uidOwner, _uidOther];

void main() {
  late Connection conn;
  late String groupId;

  Future<Object?> attempt(String uid, Future<void> Function() action) async {
    try {
      await asUser(conn, uid, action);
      return null;
    } catch (e) {
      return e;
    }
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo AE');
    await joinGroup(conn, groupId, _uidOther);
  });

  tearDownAll(() async {
    // Por dono e não por id: um caso cria Grupo próprio, e uma execução que
    // falhe no meio deixaria ele para trás e travaria o `cleanUpTestUser`.
    await conn.execute(
      Sql.named(
        'delete from public.mensagens where grupo_id in '
        '(select id from public.grupos where dono_id = any(@us::uuid[]))',
      ),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@us::uuid[])'),
      parameters: {'us': _allUids},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('assinar por outra pessoa é recusado', () async {
    final error = await attempt(
      _uidOwner,
      () => writeMessage(conn, authorId: _uidOther, groupId: groupId),
    );
    expect(error, isA<ServerException>());
  });

  test('texto vazio ou só espaço é recusado', () async {
    for (final text in ['', '   ', '\n\t ']) {
      final error = await attempt(
        _uidOwner,
        () => writeMessage(
          conn,
          authorId: _uidOwner,
          groupId: groupId,
          text: text,
        ),
      );
      expect(
        error,
        isA<ServerException>(),
        reason: 'texto=${text.length} chars',
      );
    }
  });

  test('2000 caracteres passa, 2001 não', () async {
    final id = await asUser(
      conn,
      _uidOwner,
      () => writeMessage(
        conn,
        authorId: _uidOwner,
        groupId: groupId,
        text: 'a' * 2000,
      ),
    );
    expect(id, isNotEmpty);

    final error = await attempt(
      _uidOwner,
      () => writeMessage(
        conn,
        authorId: _uidOwner,
        groupId: groupId,
        text: 'a' * 2001,
      ),
    );
    expect(error, isA<ServerException>());
  });

  test('o autor NÃO edita a própria mensagem', () async {
    final id = await asUser(
      conn,
      _uidOwner,
      () => writeMessage(
        conn,
        authorId: _uidOwner,
        groupId: groupId,
        text: 'original',
      ),
    );

    final error = await attempt(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          "update public.mensagens set texto = 'corrigido' where id = @m",
        ),
        parameters: {'m': id},
      );
    });
    expect(error, isA<ServerException>());
    expect((await messageStateOf(conn, id)).hasText, isTrue);
  });

  test('trocar espaço, autor ou data de criação é recusado', () async {
    final id = await asUser(
      conn,
      _uidOwner,
      () => writeMessage(
        conn,
        authorId: _uidOwner,
        groupId: groupId,
        text: 'fixa',
      ),
    );
    final other = await createGroup(
      conn,
      ownerId: _uidOwner,
      name: 'Grupo AE 2',
    );

    for (final (sql, params) in [
      (
        'update public.mensagens set grupo_id = @g2, texto = null where id = @m',
        {'m': id, 'g2': other},
      ),
      (
        'update public.mensagens set autor_id = @u, texto = null where id = @m',
        {'m': id, 'u': _uidOther},
      ),
      (
        "update public.mensagens set created_at = now() - interval '1 day', "
            'texto = null where id = @m',
        {'m': id},
      ),
    ]) {
      final error = await attempt(_uidOwner, () async {
        await conn.execute(Sql.named(sql), parameters: params);
      });
      expect(error, isA<ServerException>(), reason: sql);
    }

    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': other},
    );
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `denuncia-como-registro` — uma denúncia PENDENTE por (mensagem,
/// denunciante). PENDENCIAS.md 2.23: isto não é limite de ritmo — a decisão
/// de não ter limite de ritmo em denúncia continua valendo, e o teste 4.8
/// prova exatamente isso ao lado do que a unicidade recusa.

const _uidOwner = 'd7000000-0000-0000-0000-000000000001';
const _uidAuthor = 'd7000000-0000-0000-0000-000000000002';
const _uidReporter = 'd7000000-0000-0000-0000-000000000003';
const _uidOtherReporter = 'd7000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidAuthor, _uidReporter, _uidOtherReporter];

void main() {
  late Connection conn;
  late String groupId;

  Future<Object?> report(String uid, String messageId, {String? reason}) async {
    try {
      await asUser(
        conn,
        uid,
        () => conn.execute(
          Sql.named(
            'insert into public.denuncias_mensagem '
            '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
          ),
          parameters: {
            'm': messageId,
            'mo': reason ?? 'motivo de $uid sobre $messageId',
            'd': uid,
          },
        ),
      );
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo C1');
    for (final uid in [_uidAuthor, _uidReporter, _uidOtherReporter]) {
      await joinGroup(conn, groupId, uid);
    }
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

  test('4.5 — segunda denúncia pendente da mesma pessoa é recusada, '
      'com o código de erro que a tela lê', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem 4.5',
    );
    expect(await report(_uidReporter, m), isNull);

    final error = await report(_uidReporter, m);
    expect(error, isA<ServerException>());
    expect((error! as ServerException).code, 'PT423');

    final count = await conn.execute(
      Sql.named(
        'select count(*) from public.denuncias_mensagem where mensagem_id = @m',
      ),
      parameters: {'m': m},
    );
    expect(count.first[0], 1, reason: 'a segunda tentativa não gravou nada');
  });

  test('4.6 — depois do desfecho, a mesma pessoa denuncia de novo, e é aceita',
      () async {
    final m = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem 4.6',
    );
    expect(await report(_uidReporter, m), isNull);

    final id = await conn.execute(
      Sql.named(
        'select id from public.denuncias_mensagem '
        'where mensagem_id = @m and denunciante_id = @d',
      ),
      parameters: {'m': m, 'd': _uidReporter},
    );
    await asUser(
      conn,
      _uidOwner,
      () => conn.execute(
        Sql.named(
          "update public.denuncias_mensagem set estado = 'improcedente', "
          'resolvida_em = now() where id = @d',
        ),
        parameters: {'d': id.single.toColumnMap()['id']! as String},
      ),
    );

    expect(
      await report(_uidReporter, m, reason: 'fato novo depois do julgamento'),
      isNull,
      reason: 'fato novo depois de um julgamento é outro caso',
    );

    final count = await conn.execute(
      Sql.named(
        'select count(*) from public.denuncias_mensagem where mensagem_id = @m',
      ),
      parameters: {'m': m},
    );
    expect(count.first[0], 2);
  });

  test('4.7 — pessoas DIFERENTES denunciando a mesma mensagem: as duas '
      'aceitas', () async {
    final m = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem 4.7',
    );
    expect(await report(_uidReporter, m), isNull);
    expect(await report(_uidOtherReporter, m), isNull);

    final count = await conn.execute(
      Sql.named(
        'select count(*) from public.denuncias_mensagem where mensagem_id = @m',
      ),
      parameters: {'m': m},
    );
    expect(count.first[0], 2);
  });

  test('4.8 — denúncias em sequência sobre mensagens diferentes: todas '
      'aceitas — não há limite de ritmo em denúncia', () async {
    final ids = [
      for (var i = 0; i < 5; i++)
        await seedMessage(
          conn,
          authorId: _uidAuthor,
          groupId: groupId,
          text: 'mensagem 4.8.$i',
        ),
    ];
    for (final m in ids) {
      expect(await report(_uidReporter, m), isNull, reason: m);
    }
  });
}

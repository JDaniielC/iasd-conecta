import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — quem denuncia, e quem lê a denúncia.
///
/// São dois conjuntos DIFERENTES de pessoas, e o teste existe para não deixar
/// eles se confundirem. Denuncia quem lê o chat; lê a denúncia quem manda no
/// espaço. Quem denuncia não volta a ver o que escreveu, nem a própria
/// denúncia — do contrário a lista de denúncias vira um segundo canal onde a
/// conversa continua, agora sobre pessoas.
///
/// O caso que mais importa é o da AUTORA da mensagem denunciada. Ela é parte
/// interessada, não autoridade: se enxergasse a denúncia contra si, enxergaria
/// também o `update` que a resolve — e arquivar como improcedente a denúncia
/// sobre a própria mensagem é exatamente o poder que a moderação existe para
/// não dar.

const _uidOwner = 'b0000000-0000-0000-0000-000000000001';
const _uidAuthor = 'b0000000-0000-0000-0000-000000000002';
const _uidMember = 'b0000000-0000-0000-0000-000000000003';
const _uidOutsider = 'b0000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidAuthor, _uidMember, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId;
  late String messageId;

  Future<Object?> report(
    String uid, {
    String? reporter,
    String reason = 'ofensa a uma pessoa do Grupo',
  }) async {
    try {
      await asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'insert into public.denuncias_mensagem '
            '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
          ),
          parameters: {'m': messageId, 'mo': reason, 'd': reporter ?? uid},
        );
      });
      return null;
    } catch (e) {
      return e;
    }
  }

  /// Quantas denúncias a sessão de [uid] enxerga daquela linha específica.
  /// Conta por `id` e não por junção com `mensagens`: uma junção somaria a
  /// policy de `mensagens` à de `denuncias_mensagem` e o teste deixaria de
  /// dizer qual das duas recusou.
  Future<int> visibleCount(String uid, String reportId) =>
      asUser(conn, uid, () async {
        final r = await conn.execute(
          Sql.named(
            'select count(*) from public.denuncias_mensagem '
            'where id = @d',
          ),
          parameters: {'d': reportId},
        );
        return r.first[0]! as int;
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo B0');
    for (final uid in [_uidAuthor, _uidMember]) {
      await joinGroup(conn, groupId, uid);
    }
    messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'algo denunciável',
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

  test('participante do chat denuncia', () async {
    expect(await report(_uidMember), isNull);
  });

  test('motivo vazio ou só espaço é recusado', () async {
    for (final reason in ['', '   ', '\n\t']) {
      expect(
        await report(_uidMember, reason: reason),
        isA<ServerException>(),
        reason: 'motivo ${reason.codeUnits}',
      );
    }
  });

  test('assinar a denúncia por outra pessoa é recusado', () async {
    expect(
      await report(_uidMember, reporter: _uidAuthor),
      isA<ServerException>(),
    );
  });

  test('quem não lê aquele chat não denuncia', () async {
    expect(await report(_uidOutsider), isA<ServerException>());
  });

  test(
    'a lista de denúncias é de quem manda no espaço — de mais ninguém',
    () async {
      final r = await conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) '
          'values (@m, @mo, @d) returning id',
        ),
        parameters: {
          'm': messageId,
          'mo': 'marcador da leitura de denúncia',
          'd': _uidMember,
        },
      );
      final reportId = r.single.toColumnMap()['id']! as String;

      expect(
        await visibleCount(_uidOwner, reportId),
        1,
        reason: 'a dona do Grupo é a autoridade do espaço',
      );
      expect(
        await visibleCount(_uidMember, reportId),
        0,
        reason: 'quem denunciou não relê a própria denúncia',
      );
      expect(
        await visibleCount(_uidAuthor, reportId),
        0,
        reason: 'a autora da mensagem denunciada é parte, não autoridade',
      );
      expect(
        await visibleCount(_uidOutsider, reportId),
        0,
        reason: 'quem nem lê o chat não lê denúncia dele',
      );
    },
  );

  test(
    'a autora da mensagem denunciada não resolve a denúncia contra si',
    () async {
      final r = await conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) '
          'values (@m, @mo, @d) returning id',
        ),
        parameters: {
          'm': messageId,
          'mo': 'marcador da resolução de denúncia',
          'd': _uidMember,
        },
      );
      final reportId = r.single.toColumnMap()['id']! as String;

      // Recusa por RLS de update é ZERO LINHA, não erro.
      final affected = await asUser(conn, _uidAuthor, () async {
        final x = await conn.execute(
          Sql.named(
            "update public.denuncias_mensagem set estado = 'improcedente', "
            'resolvida_em = now() where id = @d',
          ),
          parameters: {'d': reportId},
        );
        return x.affectedRows;
      });
      expect(affected, 0);

      final state = await conn.execute(
        Sql.named('select estado from public.denuncias_mensagem where id = @d'),
        parameters: {'d': reportId},
      );
      expect(state.single.toColumnMap()['estado'], 'pendente');
    },
  );
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `denuncia-como-registro` — a denúncia registrada não se reescreve.
///
/// Medido em PENDENCIAS.md 2.24: até esta migration, o dono de um Grupo
/// reescrevia o `motivo` de uma denúncia alheia e trocava `denunciante_id`
/// para si mesmo, os dois ACEITOS. `denuncias_mensagem_so_resolve_trigger`
/// fecha os dois — e o resolver (`estado`/`resolvida_em`) continua aceito, que
/// é o contraste sem o qual os testes de cima passariam com a tabela travada
/// inteira.
///
/// CADA TESTE DENUNCIA UMA MENSAGEM PRÓPRIA, e não é estilo: a change irmã
/// (`denuncia-como-registro`, seção 2) também restringe uma pendente por
/// (mensagem, denunciante), e reusar a mesma mensagem entre testes deste
/// arquivo colidiria com AQUELA regra em vez de exercitar só esta.

const _uidOwner = 'c0000000-0000-0000-0000-000000000001';
const _uidAuthor = 'c0000000-0000-0000-0000-000000000002';
const _uidReporter = 'c0000000-0000-0000-0000-000000000003';
const _uidOtherMember = 'c0000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidAuthor, _uidReporter, _uidOtherMember];

void main() {
  late Connection conn;
  late String groupId;

  /// Insere PELA SESSÃO DO DENUNCIANTE, sem `returning`. Não é estilo: quem
  /// denunciou não tem `select` liberado pela RLS na própria denúncia
  /// (`denuncias_mensagem_select_autoridade` só alcança autoridade), e
  /// `insert ... returning` exige que a linha passe pela policy de SELECT —
  /// diferente de `update`/`delete`, que filtrariam em silêncio, o `insert`
  /// LEVANTA `new row violates row-level security policy` quando a policy de
  /// select nega a linha recém-criada. É por isso que
  /// `ChatRepository.reportMessage` nunca chama `.select()` depois do
  /// `insert`. O id sai por [_idOf], lido como `postgres`.
  Future<void> report(
    String uid,
    String messageId, {
    String reason = 'ofensa',
  }) => asUser(
    conn,
    uid,
    () => conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
      ),
      parameters: {'m': messageId, 'mo': reason, 'd': uid},
    ),
  );

  /// O id da denúncia daquele par, lido como `postgres` — quem denunciou não
  /// teria como ler de volta.
  Future<String> idOf(String messageId, String denunciante) async {
    final r = await conn.execute(
      Sql.named(
        'select id from public.denuncias_mensagem '
        'where mensagem_id = @m and denunciante_id = @d',
      ),
      parameters: {'m': messageId, 'd': denunciante},
    );
    return r.single.toColumnMap()['id']! as String;
  }

  /// `affectedRows`, não `throwsA` — recusa de RLS num `update` é ZERO LINHA,
  /// não erro. As colunas travadas aqui recusam por GATILHO, que É exceção;
  /// por isso as duas formas aparecem nos testes abaixo conforme quem tenta.
  Future<int> updateAs(
    String uid,
    String reportId,
    String setClause,
    Map<String, Object?> params,
  ) => asUser(conn, uid, () async {
    final r = await conn.execute(
      Sql.named(
        'update public.denuncias_mensagem set $setClause where id = @d',
      ),
      parameters: {'d': reportId, ...params},
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
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo C0');
    for (final uid in [_uidAuthor, _uidReporter, _uidOtherMember]) {
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

  test('4.1a — a autoridade do espaço não reescreve o motivo', () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    await report(_uidReporter, m, reason: 'motivo original');
    final id = await idOf(m, _uidReporter);

    // Recusa por GATILHO é exceção — a RLS de update deixaria passar até
    // aqui, e é o gatilho quem barra. `await expectLater` (nunca `expect` com
    // uma closure não esperada): sem o `await`, a asserção roda em segundo
    // plano e a leitura seguinte, na MESMA conexão, corre com o próprio
    // `updateAs` — que muda o `role` da sessão. Medido: a corrida fazia o
    // `select` de baixo rodar sob `role authenticated` sem claims, e devolvia
    // ZERO linhas por RLS, derrubando o teste por um motivo que não é o dele.
    await expectLater(
      updateAs(_uidOwner, id, 'motivo = @m', {'m': 'motivo trocado'}),
      throwsA(isA<ServerException>()),
    );
    final row = await conn.execute(
      Sql.named('select motivo from public.denuncias_mensagem where id = @d'),
      parameters: {'d': id},
    );
    expect(row.single.toColumnMap()['motivo'], 'motivo original');
  });

  test(
    '4.1b — o próprio denunciante não reescreve o motivo — RLS não '
    'alcança, ainda por cima',
    () async {
      final m = await seedMessage(
        conn,
        authorId: _uidAuthor,
        groupId: groupId,
      );
      await report(_uidReporter, m, reason: 'meu motivo original');
      final id = await idOf(m, _uidReporter);

      // Quem denunciou não tem `update` liberado pela RLS nenhuma: a recusa
      // aqui é AUSÊNCIA (zero linha), antes mesmo do gatilho.
      final affected = await updateAs(_uidReporter, id, 'motivo = @m', {
        'm': 'reescrito por quem denunciou',
      });
      expect(affected, 0);
      final row = await conn.execute(
        Sql.named(
          'select motivo from public.denuncias_mensagem where id = @d',
        ),
        parameters: {'d': id},
      );
      expect(row.single.toColumnMap()['motivo'], 'meu motivo original');
    },
  );

  test('4.2 — trocar quem denunciou é recusado', () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    await report(_uidReporter, m, reason: 'para o teste de 4.2');
    final id = await idOf(m, _uidReporter);

    await expectLater(
      updateAs(_uidOwner, id, 'denunciante_id = @u', {'u': _uidOwner}),
      throwsA(isA<ServerException>()),
    );
    final row = await conn.execute(
      Sql.named(
        'select denunciante_id::text from public.denuncias_mensagem '
        'where id = @d',
      ),
      parameters: {'d': id},
    );
    expect(row.single.toColumnMap()['denunciante_id'], _uidReporter);
  });

  test('4.3a — apontar para outra mensagem é recusado', () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    final other = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
    );
    await report(_uidReporter, m, reason: 'para o teste de 4.3a');
    final id = await idOf(m, _uidReporter);

    await expectLater(
      updateAs(_uidOwner, id, 'mensagem_id = @m', {'m': other}),
      throwsA(isA<ServerException>()),
    );
    final row = await conn.execute(
      Sql.named(
        'select mensagem_id::text from public.denuncias_mensagem '
        'where id = @d',
      ),
      parameters: {'d': id},
    );
    expect(row.single.toColumnMap()['mensagem_id'], m);
  });

  test('4.3b — alterar created_at é recusado', () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    await report(_uidReporter, m, reason: 'para o teste de 4.3b');
    final id = await idOf(m, _uidReporter);

    final before = await conn.execute(
      Sql.named(
        'select created_at from public.denuncias_mensagem where id = @d',
      ),
      parameters: {'d': id},
    );
    await expectLater(
      updateAs(_uidOwner, id, "created_at = now() - interval '1 year'", {}),
      throwsA(isA<ServerException>()),
    );
    final after = await conn.execute(
      Sql.named(
        'select created_at from public.denuncias_mensagem where id = @d',
      ),
      parameters: {'d': id},
    );
    expect(
      after.single.toColumnMap()['created_at'],
      before.single.toColumnMap()['created_at'],
    );
  });

  test('4.4 — o desfecho continua alterável por quem tem autoridade',
      () async {
    final m = await seedMessage(conn, authorId: _uidAuthor, groupId: groupId);
    await report(_uidReporter, m, reason: 'para o teste de 4.4');
    final id = await idOf(m, _uidReporter);

    final affected = await updateAs(
      _uidOwner,
      id,
      "estado = 'improcedente', resolvida_em = now()",
      {},
    );
    expect(affected, 1);
    final row = await conn.execute(
      Sql.named('select estado from public.denuncias_mensagem where id = @d'),
      parameters: {'d': id},
    );
    expect(row.single.toColumnMap()['estado'], 'improcedente');
  });
}

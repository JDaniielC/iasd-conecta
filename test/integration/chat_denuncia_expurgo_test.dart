import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `denuncia-como-registro` — o motivo tem prazo, contado do DESFECHO.
///
/// `expurgar_motivos_de_denuncia()` é GLOBAL — varre a tabela inteira, não só
/// as linhas deste arquivo, e `dart test` roda os arquivos em paralelo. Por
/// isso toda asserção é sobre linha identificada por id, nunca sobre o número
/// que a função devolve.
///
/// As linhas nascem via `insert` direto como `postgres`, com `resolvida_em`
/// já no passado — é a única forma de simular "31 dias depois do desfecho"
/// sem esperar 31 dias. O gatilho de imutabilidade é `before UPDATE`, não
/// `before INSERT`, então este `insert` não passa por ele.

const _uidAuthor = 'd8000000-0000-0000-0000-000000000001';
const _uidReporter = 'd8000000-0000-0000-0000-000000000002';
const _allUids = [_uidAuthor, _uidReporter];

void main() {
  late Connection conn;
  late String groupId;
  late String messageId;

  Future<String> seedResolved({
    required String estado,
    DateTime? resolvedAt,
  }) async {
    final r = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id, estado, resolvida_em) '
        'values (@m, @mo, @d, @e, @r) returning id',
      ),
      parameters: {
        'm': messageId,
        'mo': 'motivo de teste do expurgo',
        'd': _uidReporter,
        'e': estado,
        'r': resolvedAt,
      },
    );
    return r.single.toColumnMap()['id']! as String;
  }

  Future<String?> motivoOf(String id) async {
    final r = await conn.execute(
      Sql.named('select motivo from public.denuncias_mensagem where id = @d'),
      parameters: {'d': id},
    );
    return r.single.toColumnMap()['motivo'] as String?;
  }

  Future<void> purge() async {
    await conn.execute('select public.expurgar_motivos_de_denuncia()');
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
    groupId = await createGroup(conn, ownerId: _uidAuthor, name: 'Grupo C2');
    await joinGroup(conn, groupId, _uidReporter);
    messageId = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem do expurgo de motivo',
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
    '4.9 — denúncia julgada passada do prazo perde o motivo e mantém '
    'estado e resolvida_em',
    () async {
      final resolvedAt = DateTime.now().toUtc().subtract(
        const Duration(days: 31),
      );
      final id = await seedResolved(
        estado: 'improcedente',
        resolvedAt: resolvedAt,
      );

      expect(
        await motivoOf(id),
        isNotNull,
        reason: 'contagem ANTES é o outro lado da prova',
      );

      await purge();

      expect(await motivoOf(id), isNull);
      final row = await conn.execute(
        Sql.named(
          'select estado, resolvida_em from public.denuncias_mensagem '
          'where id = @d',
        ),
        parameters: {'d': id},
      );
      final r = row.single.toColumnMap();
      expect(r['estado'], 'improcedente');
      expect(r['resolvida_em'], isNotNull);
    },
  );

  test('4.10 — denúncia PENDENTE passada do mesmo prazo mantém o motivo',
      () async {
    final id = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id, estado, created_at) '
        "values (@m, @mo, @d, 'pendente', now() - interval '400 days') "
        'returning id',
      ),
      parameters: {
        'm': messageId,
        'mo': 'motivo pendente antigo, nunca julgado',
        'd': _uidReporter,
      },
    ).then((r) => r.single.toColumnMap()['id']! as String);

    await purge();

    expect(
      await motivoOf(id),
      'motivo pendente antigo, nunca julgado',
      reason: 'pendente que some sem desfecho é o pior resultado para quem '
          'denunciou — a razão de contar do desfecho, não da criação',
    );
  });
}

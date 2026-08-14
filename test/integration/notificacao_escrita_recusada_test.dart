import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — o cliente escreve UMA coluna, e só na própria
/// linha.
///
/// Duas barreiras diferentes, e o teste separa as duas porque elas falham por
/// motivos diferentes:
///   - `insert` e `delete` caem por AUSÊNCIA de policy e de grant;
///   - `update` de `tipo`/`ator_id`/`destinatario_id` cai por PRIVILÉGIO DE
///     COLUNA, antes de qualquer regra de linha.
///
/// A segunda é a lição de `20260811160000_grant_update_perfis_por_coluna.sql`:
/// lá a policy protegia a linha, o grant não recortava a coluna, e dava para
/// forjar a própria `idade`.

const _uidDona = 'f3000000-0000-0000-0000-000000000001';
const _uidOutra = 'f3000000-0000-0000-0000-000000000002';
const _allUids = [_uidDona, _uidOutra];

void main() {
  late Connection conn;

  Future<Object?> comoDona(String sql) async {
    try {
      await asUser(conn, _uidDona, () async {
        await conn.execute(Sql.named(sql), parameters: {'d': _uidDona});
      });
      return null;
    } catch (e) {
      return e;
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona F3');
    await createTestProfile(conn, _uidOutra, name: 'Outra F3');
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo, ator_id) "
        "values (@d, 'convite_recebido', @a)",
      ),
      parameters: {'d': _uidDona, 'a': _uidOutra},
    );
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('inserir é recusado, inclusive para si mesma', () async {
    expect(
      await comoDona(
          "insert into public.notificacoes (destinatario_id, tipo) values (@d, 'convite_recebido')"),
      isA<ServerException>(),
    );
  });

  test('apagar é recusado, inclusive a própria linha', () async {
    expect(
      await comoDona('delete from public.notificacoes where destinatario_id = @d'),
      isA<ServerException>(),
    );
  });

  test('mudar tipo, ator ou destinatário é recusado por privilégio de coluna',
      () async {
    for (final sql in [
      "update public.notificacoes set tipo = 'convite_aceito' where destinatario_id = @d",
      'update public.notificacoes set ator_id = @d where destinatario_id = @d',
      'update public.notificacoes set destinatario_id = @d where destinatario_id = @d',
    ]) {
      expect(await comoDona(sql), isA<ServerException>(), reason: sql);
    }
  });

  test('marcar a própria como lida funciona — é a única escrita permitida',
      () async {
    expect(
      await comoDona(
          'update public.notificacoes set lida_em = now() where destinatario_id = @d'),
      isNull,
    );
    final r = await conn.execute(
      Sql.named('select lida_em from public.notificacoes where destinatario_id = @d'),
      parameters: {'d': _uidDona},
    );
    expect(r.single.toColumnMap()['lida_em'], isNotNull);
  });

  test('marcar a de outra pessoa como lida não afeta nada, e não dá erro',
      () async {
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo) values (@o, 'convite_recebido')",
      ),
      parameters: {'o': _uidOutra},
    );
    final afetadas = await asUser(conn, _uidDona, () async {
      final r = await conn.execute(
        Sql.named('update public.notificacoes set lida_em = now() where destinatario_id = @o'),
        parameters: {'o': _uidOutra},
      );
      return r.affectedRows;
    });
    expect(afetadas, 0, reason: 'a policy recusa por linha, sem erro');
  });
}

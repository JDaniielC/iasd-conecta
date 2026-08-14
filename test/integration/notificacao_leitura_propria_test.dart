import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — aviso é dirigido e privado.
///
/// A tabela e a VIEW são testadas separadamente de propósito. A view é o caminho
/// que o app usa, e é o que pode ignorar a RLS: sem `security_invoker = true`
/// ela roda com os privilégios de quem a criou e entrega aviso alheio. É a linha
/// mais perigosa da change, e a única forma de saber é perguntar pelas duas
/// portas.

const _uidAna = 'f1000000-0000-0000-0000-000000000001';
const _uidBeto = 'f1000000-0000-0000-0000-000000000002';
const _allUids = [_uidAna, _uidBeto];

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAna, name: 'Ana F1');
    await createTestProfile(conn, _uidBeto, name: 'Beto F1');
    for (final (dono, ator) in [(_uidAna, _uidBeto), (_uidBeto, _uidAna)]) {
      await conn.execute(
        Sql.named(
          "insert into public.notificacoes (destinatario_id, tipo, ator_id) "
          "values (@d, 'convite_recebido', @a)",
        ),
        parameters: {'d': dono, 'a': ator},
      );
    }
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('pela tabela, cada uma vê só a própria', () async {
    final daAna = await asUser(conn, _uidAna, () => notificacoesVisiveis(conn));
    final doBeto = await asUser(conn, _uidBeto, () => notificacoesVisiveis(conn));
    expect(daAna.map((n) => n['destinatario_id']), [_uidAna]);
    expect(doBeto.map((n) => n['destinatario_id']), [_uidBeto]);
  });

  test('pela view, cada uma vê só a própria — security_invoker valendo',
      () async {
    final daAna = await asUser(conn, _uidAna, () => notificacoesAtivas(conn));
    final doBeto = await asUser(conn, _uidBeto, () => notificacoesAtivas(conn));
    expect(daAna.map((n) => n['destinatario_id']), [_uidAna]);
    expect(doBeto.map((n) => n['destinatario_id']), [_uidBeto]);
  });

  test('a view está declarada com security_invoker — o que sustenta o caso '
      'acima', () async {
    final r = await conn.execute(
      "select reloptions from pg_class where relname = 'notificacoes_ativas'",
    );
    expect(r.single.toColumnMap()['reloptions'], contains('security_invoker=true'));
  });
}

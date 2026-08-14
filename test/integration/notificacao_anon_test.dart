import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — `anon` não alcança aviso nenhum.
///
/// Diferente de `acoes` e `votos`, aqui NÃO vale o argumento de canal lateral
/// que fez a feature 021 manter o `grant` de `anon`: ninguém descobre a
/// existência de um aviso alheio por diferença de resposta, porque não há id de
/// aviso circulando fora do dono. Então `anon` não recebe grant nenhum, e a
/// recusa é por privilégio.

const _uidDona = 'f2000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona F2');
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo) "
        "values (@d, 'convite_recebido')",
      ),
      parameters: {'d': _uidDona},
    );
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, [_uidDona]);
    await cleanUpTestUser(conn, _uidDona);
    await conn.close();
  });

  test('anon não lê a tabela', () async {
    Object? erro;
    try {
      await asVisitor(conn, () => notificacoesVisiveis(conn));
    } catch (e) {
      erro = e;
    }
    expect(erro, isA<ServerException>());
  });

  test('anon não lê a view', () async {
    Object? erro;
    try {
      await asVisitor(conn, () => notificacoesAtivas(conn));
    } catch (e) {
      erro = e;
    }
    expect(erro, isA<ServerException>());
  });
}

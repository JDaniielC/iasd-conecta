import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  Future<bool> nomeValido(String name) async {
    final rows = await conn.execute(
      Sql.named('select public.nome_valido(@nome) as valido'),
      parameters: {'nome': name},
    );
    return rows.single.toColumnMap()['valido'] as bool;
  }

  test('FR-002: rejeita nome com palavra da lista de bloqueio', () async {
    expect(await nomeValido('João Idiota Silva'), isFalse);
  });

  test('FR-002: aceita nome sem palavra bloqueada', () async {
    expect(await nomeValido('João Silva'), isTrue);
  });

  test('FR-002: moderação ignora maiúsculas/minúsculas', () async {
    expect(await nomeValido('Maria IDIOTA Souza'), isFalse);
  });
}

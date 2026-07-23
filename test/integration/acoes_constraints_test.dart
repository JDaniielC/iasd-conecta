import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '50000000-0000-0000-0000-000000000010';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarPerfilDeTeste(conn, _uidCriador, nome: 'Criador Constraints'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidCriador},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
  });

  test('FR-001: insert em acoes com nome em branco falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id) "
          "values ('   ', now() + interval '7 days', 'Sede', @criador)",
        ),
        parameters: {'criador': _uidCriador},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('acao válida (sem detalhes/limite) é aceita', () async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Acampamento', now() + interval '7 days', 'Sítio', @criador) "
        "returning nome",
      ),
      parameters: {'criador': _uidCriador},
    );
    expect(rows.single.toColumnMap()['nome'], 'Acampamento');
  });

  test('limite_vagas zero ou negativo falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) "
          "values ('Mutirão', now() + interval '7 days', 'Bairro', 0, @criador)",
        ),
        parameters: {'criador': _uidCriador},
      ),
      throwsA(isA<ServerException>()),
    );
  });
}

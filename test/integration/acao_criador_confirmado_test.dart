import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '50000000-0000-0000-0000-000000000011';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarPerfilDeTeste(conn, _uidCriador, nome: 'Criador Auto'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidCriador},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
  });

  test(
    'FR-013: criar Ação confirma automaticamente o criador',
    () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id) "
          "values ('Retiro', now() + interval '10 days', 'Chácara', @criador) "
          "returning id",
        ),
        parameters: {'criador': _uidCriador},
      );
      final acaoId = rows.single.toColumnMap()['id'];

      final confirmacoes = await conn.execute(
        Sql.named('select usuario_id, status from public.confirmacoes_acao where acao_id = @acao'),
        parameters: {'acao': acaoId},
      );

      expect(confirmacoes, hasLength(1));
      final row = confirmacoes.single.toColumnMap();
      expect(row['usuario_id'], _uidCriador);
      expect(row['status'], 'confirmado');
    },
  );
}

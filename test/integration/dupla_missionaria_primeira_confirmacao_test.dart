import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '60000000-0000-0000-0000-000000000020';

Future<String> _criarDuplaMissionaria(
  Connection conn, {
  required String creatorId,
  required String generoVisitado,
}) async {
  final rows = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
      "eh_dupla_missionaria, genero_visitado) "
      "values ('Visita PrimeiraConfirmacao', now() + interval '1 day', 'Casa', @criador, 2, "
      "true, @genero) returning id",
    ),
    parameters: {'criador': creatorId, 'genero': generoVisitado},
  );
  return rows.single.toColumnMap()['id']! as String;
}

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidCriador},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
  });

  test('FR-007: primeira confirmação (o próprio criador) é sempre aceita, qualquer gênero',
      () async {
    await criarPerfilDeTeste(conn, _uidCriador, name: 'Criador PrimeiraConfirmacao', gender: 'masculino');
    final acaoId = await _criarDuplaMissionaria(
      conn,
      creatorId: _uidCriador,
      generoVisitado: 'feminino',
    );

    final rows = await conn.execute(
      Sql.named(
        'select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
      ),
      parameters: {'acao': acaoId, 'uid': _uidCriador},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });
}

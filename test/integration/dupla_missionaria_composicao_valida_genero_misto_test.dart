import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidHomem = '60000000-0000-0000-0000-000000000040';
const _uidMulher = '60000000-0000-0000-0000-000000000041';

Future<String> _createMissionaryPair(
  Connection conn, {
  required String creatorId,
  required String visitedGender,
}) async {
  final rows = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
      "eh_dupla_missionaria, genero_visitado) "
      "values ('Visita GeneroMisto', now() + interval '1 day', 'Casa', @criador, 2, "
      "true, @genero) returning id",
    ),
    parameters: {'criador': creatorId, 'genero': visitedGender},
  );
  return rows.single.toColumnMap()['id']! as String;
}

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidHomem, name: 'Homem GeneroMisto', gender: 'masculino');
    await createTestProfile(conn, _uidMulher, name: 'Mulher GeneroMisto', gender: 'feminino');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id in (@h, @m)'),
      parameters: {'h': _uidHomem, 'm': _uidMulher},
    );
    await cleanUpTestUser(conn, _uidHomem);
    await cleanUpTestUser(conn, _uidMulher);
    await conn.close();
  });

  test('FR-004: 1 homem + 1 mulher é válida visitando homem', () async {
    final actionId = await _createMissionaryPair(conn, creatorId: _uidHomem, visitedGender: 'masculino');
    await asUser(conn, _uidMulher, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidMulher},
      );
    });
    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': actionId, 'uid': _uidMulher},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });

  test('FR-004: 1 homem + 1 mulher é válida visitando mulher', () async {
    final actionId = await _createMissionaryPair(conn, creatorId: _uidMulher, visitedGender: 'feminino');
    await asUser(conn, _uidHomem, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidHomem},
      );
    });
    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': actionId, 'uid': _uidHomem},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });
}

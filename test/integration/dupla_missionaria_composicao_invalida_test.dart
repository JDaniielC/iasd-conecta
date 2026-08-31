import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidHomem1 = '60000000-0000-0000-0000-000000000050';
const _uidHomem2 = '60000000-0000-0000-0000-000000000051';
const _uidMulher1 = '60000000-0000-0000-0000-000000000052';
const _uidMulher2 = '60000000-0000-0000-0000-000000000053';

Future<String> _createMissionaryPair(
  Connection conn, {
  required String creatorId,
  required String visitedGender,
}) async {
  final rows = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
      "eh_dupla_missionaria, genero_visitado) "
      "values ('Visita ComposicaoInvalida', now() + interval '1 day', 'Casa', @criador, 2, "
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
    await createTestProfile(conn, _uidHomem1, name: 'Homem1 Invalida', gender: 'masculino');
    await createTestProfile(conn, _uidHomem2, name: 'Homem2 Invalida', gender: 'masculino');
    await createTestProfile(conn, _uidMulher1, name: 'Mulher1 Invalida', gender: 'feminino');
    await createTestProfile(conn, _uidMulher2, name: 'Mulher2 Invalida', gender: 'feminino');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id in (@h1, @m1)'),
      parameters: {'h1': _uidHomem1, 'm1': _uidMulher1},
    );
    await cleanUpTestUser(conn, _uidHomem1);
    await cleanUpTestUser(conn, _uidHomem2);
    await cleanUpTestUser(conn, _uidMulher1);
    await cleanUpTestUser(conn, _uidMulher2);
    await conn.close();
  });

  test('FR-005/FR-006: 2 homens visitando mulher é recusada', () async {
    final actionId = await _createMissionaryPair(conn, creatorId: _uidHomem1, visitedGender: 'feminino');
    await expectLater(
      asUser(conn, _uidHomem2, () async {
        await conn.execute(
          Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
          parameters: {'acao': actionId, 'uid': _uidHomem2},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-005/FR-006: 2 mulheres visitando homem é recusada', () async {
    final actionId = await _createMissionaryPair(conn, creatorId: _uidMulher1, visitedGender: 'masculino');
    await expectLater(
      asUser(conn, _uidMulher2, () async {
        await conn.execute(
          Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
          parameters: {'acao': actionId, 'uid': _uidMulher2},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

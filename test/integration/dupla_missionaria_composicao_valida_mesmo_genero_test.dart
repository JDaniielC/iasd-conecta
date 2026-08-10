import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidHomem1 = '60000000-0000-0000-0000-000000000030';
const _uidHomem2 = '60000000-0000-0000-0000-000000000031';
const _uidMulher1 = '60000000-0000-0000-0000-000000000032';
const _uidMulher2 = '60000000-0000-0000-0000-000000000033';

Future<void> _asUser(Connection conn, String uid, Future<void> Function() action) async {
  await conn.execute('set role authenticated');
  await conn.execute("set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await action();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

Future<String> _createMissionaryPair(
  Connection conn, {
  required String creatorId,
  required String visitedGender,
}) async {
  final rows = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
      "eh_dupla_missionaria, genero_visitado) "
      "values ('Visita ComposicaoMesmoGenero', now() + interval '1 day', 'Casa', @criador, 2, "
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
    await createTestProfile(conn, _uidHomem1, name: 'Homem1 MesmoGenero', gender: 'masculino');
    await createTestProfile(conn, _uidHomem2, name: 'Homem2 MesmoGenero', gender: 'masculino');
    await createTestProfile(conn, _uidMulher1, name: 'Mulher1 MesmoGenero', gender: 'feminino');
    await createTestProfile(conn, _uidMulher2, name: 'Mulher2 MesmoGenero', gender: 'feminino');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.acoes where criador_id in (@h1, @m1)',
      ),
      parameters: {'h1': _uidHomem1, 'm1': _uidMulher1},
    );
    await cleanUpTestUser(conn, _uidHomem1);
    await cleanUpTestUser(conn, _uidHomem2);
    await cleanUpTestUser(conn, _uidMulher1);
    await cleanUpTestUser(conn, _uidMulher2);
    await conn.close();
  });

  test('FR-004: 2 homens visitando homem é uma composição válida', () async {
    final actionId = await _createMissionaryPair(
      conn,
      creatorId: _uidHomem1,
      visitedGender: 'masculino',
    );
    await _asUser(conn, _uidHomem2, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidHomem2},
      );
    });
    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': actionId, 'uid': _uidHomem2},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });

  test('FR-004: 2 mulheres visitando mulher é uma composição válida', () async {
    final actionId = await _createMissionaryPair(
      conn,
      creatorId: _uidMulher1,
      visitedGender: 'feminino',
    );
    await _asUser(conn, _uidMulher2, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidMulher2},
      );
    });
    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': actionId, 'uid': _uidMulher2},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });
}

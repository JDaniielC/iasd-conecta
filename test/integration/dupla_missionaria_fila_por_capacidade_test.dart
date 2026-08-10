import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidHomem1 = '60000000-0000-0000-0000-000000000060';
const _uidMulher1 = '60000000-0000-0000-0000-000000000061';
const _uidTerceiro = '60000000-0000-0000-0000-000000000062';

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

void main() {
  late Connection conn;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidHomem1, name: 'Homem1 FilaCapacidade', gender: 'masculino');
    await createTestProfile(conn, _uidMulher1, name: 'Mulher1 FilaCapacidade', gender: 'feminino');
    await createTestProfile(conn, _uidTerceiro, name: 'Terceiro FilaCapacidade', gender: 'masculino');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
        "eh_dupla_missionaria, genero_visitado) "
        "values ('Visita FilaCapacidade', now() + interval '1 day', 'Casa', @criador, 2, "
        "true, 'feminino') returning id",
      ),
      parameters: {'criador': _uidHomem1},
    );
    actionId = rows.single.toColumnMap()['id']! as String;

    // 1H + 1M já preenche as 2 vagas validamente.
    await _asUser(conn, _uidMulher1, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidMulher1},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidHomem1},
    );
    await cleanUpTestUser(conn, _uidHomem1);
    await cleanUpTestUser(conn, _uidMulher1);
    await cleanUpTestUser(conn, _uidTerceiro);
    await conn.close();
  });

  test('Edge Case: com as 2 vagas válidas preenchidas, uma 3ª tentativa vai pra fila, não é recusada por gênero',
      () async {
    await _asUser(conn, _uidTerceiro, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': actionId, 'uid': _uidTerceiro},
      );
    });
    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': actionId, 'uid': _uidTerceiro},
    );
    expect(rows.single.toColumnMap()['status'], 'fila');
  });
}

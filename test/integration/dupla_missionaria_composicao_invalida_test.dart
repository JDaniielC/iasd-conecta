import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidHomem1 = '60000000-0000-0000-0000-000000000050';
const _uidHomem2 = '60000000-0000-0000-0000-000000000051';
const _uidMulher1 = '60000000-0000-0000-0000-000000000052';
const _uidMulher2 = '60000000-0000-0000-0000-000000000053';

Future<void> _comoUsuario(Connection conn, String uid, Future<void> Function() action) async {
  await conn.execute('set role authenticated');
  await conn.execute("set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await action();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

Future<String> _criarDuplaMissionaria(
  Connection conn, {
  required String creatorId,
  required String generoVisitado,
}) async {
  final rows = await conn.execute(
    Sql.named(
      "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
      "eh_dupla_missionaria, genero_visitado) "
      "values ('Visita ComposicaoInvalida', now() + interval '1 day', 'Casa', @criador, 2, "
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
    await criarPerfilDeTeste(conn, _uidHomem1, name: 'Homem1 Invalida', gender: 'masculino');
    await criarPerfilDeTeste(conn, _uidHomem2, name: 'Homem2 Invalida', gender: 'masculino');
    await criarPerfilDeTeste(conn, _uidMulher1, name: 'Mulher1 Invalida', gender: 'feminino');
    await criarPerfilDeTeste(conn, _uidMulher2, name: 'Mulher2 Invalida', gender: 'feminino');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id in (@h1, @m1)'),
      parameters: {'h1': _uidHomem1, 'm1': _uidMulher1},
    );
    await limparUsuarioDeTeste(conn, _uidHomem1);
    await limparUsuarioDeTeste(conn, _uidHomem2);
    await limparUsuarioDeTeste(conn, _uidMulher1);
    await limparUsuarioDeTeste(conn, _uidMulher2);
    await conn.close();
  });

  test('FR-005/FR-006: 2 homens visitando mulher é recusada', () async {
    final acaoId = await _criarDuplaMissionaria(conn, creatorId: _uidHomem1, generoVisitado: 'feminino');
    await expectLater(
      _comoUsuario(conn, _uidHomem2, () async {
        await conn.execute(
          Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
          parameters: {'acao': acaoId, 'uid': _uidHomem2},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-005/FR-006: 2 mulheres visitando homem é recusada', () async {
    final acaoId = await _criarDuplaMissionaria(conn, creatorId: _uidMulher1, generoVisitado: 'masculino');
    await expectLater(
      _comoUsuario(conn, _uidMulher2, () async {
        await conn.execute(
          Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
          parameters: {'acao': acaoId, 'uid': _uidMulher2},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

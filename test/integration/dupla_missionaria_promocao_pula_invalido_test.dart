import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidHomemA = '60000000-0000-0000-0000-000000000070';
const _uidMulherB = '60000000-0000-0000-0000-000000000071';
const _uidHomemC = '60000000-0000-0000-0000-000000000072';
const _uidMulherD = '60000000-0000-0000-0000-000000000073';

Future<void> _comoUsuario(Connection conn, String uid, Future<void> Function() acao) async {
  await conn.execute('set role authenticated');
  await conn.execute("set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await acao();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

void main() {
  late Connection conn;
  late String acaoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidHomemA, name: 'HomemA PromocaoPulaInvalido', gender: 'masculino');
    await criarPerfilDeTeste(conn, _uidMulherB, name: 'MulherB PromocaoPulaInvalido', gender: 'feminino');
    await criarPerfilDeTeste(conn, _uidHomemC, name: 'HomemC PromocaoPulaInvalido', gender: 'masculino');
    await criarPerfilDeTeste(conn, _uidMulherD, name: 'MulherD PromocaoPulaInvalido', gender: 'feminino');

    // Dupla visitando mulher: A (homem, criador) + B (mulher) = 1H+1M válido.
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas, "
        "eh_dupla_missionaria, genero_visitado) "
        "values ('Visita PromocaoPulaInvalido', now() + interval '1 day', 'Casa', @criador, 2, "
        "true, 'feminino') returning id",
      ),
      parameters: {'criador': _uidHomemA},
    );
    acaoId = rows.single.toColumnMap()['id']! as String;

    await _comoUsuario(conn, _uidMulherB, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': acaoId, 'uid': _uidMulherB},
      );
    });

    // C (homem) entra na fila primeiro — formaria 2H visitando mulher, inválido.
    await _comoUsuario(conn, _uidHomemC, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': acaoId, 'uid': _uidHomemC},
      );
    });
    // D (mulher) entra na fila depois — formaria 2M visitando mulher, válido.
    await _comoUsuario(conn, _uidMulherD, () async {
      await conn.execute(
        Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @uid)'),
        parameters: {'acao': acaoId, 'uid': _uidMulherD},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @criador'),
      parameters: {'criador': _uidHomemA},
    );
    await limparUsuarioDeTeste(conn, _uidHomemA);
    await limparUsuarioDeTeste(conn, _uidMulherB);
    await limparUsuarioDeTeste(conn, _uidHomemC);
    await limparUsuarioDeTeste(conn, _uidMulherD);
    await conn.close();
  });

  test('FR-009: ao desistir, a promoção pula o candidato inválido da fila e promove o próximo válido',
      () async {
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid'),
      parameters: {'acao': acaoId, 'uid': _uidMulherB},
    );

    final rows = await conn.execute(
      Sql.named('select usuario_id, status from public.confirmacoes_acao where acao_id = @acao'),
      parameters: {'acao': acaoId},
    );
    final statusMap = {for (final r in rows) r.toColumnMap()['usuario_id']: r.toColumnMap()['status']};

    expect(statusMap[_uidHomemC], 'fila', reason: 'HomemC deve continuar na fila (seria inválido)');
    expect(statusMap[_uidMulherD], 'confirmado', reason: 'MulherD deve ser promovida (1H+1M válido)');
  });
}

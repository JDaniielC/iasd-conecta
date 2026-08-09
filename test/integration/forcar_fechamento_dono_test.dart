import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000025';
const _uidParticipante = '70000000-0000-0000-0000-000000000026';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono ForcarFechamento');
    await criarPerfilDeTeste(conn, _uidParticipante, name: 'Participante ForcarFechamento');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ForcarFechamento', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = grupoRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidParticipante},
    );

    late Object votingRound;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidDono},
      );
      votingRound = rows.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await conn.close();
  });

  test('FR-010: participante que não é Dono não força fechamento', () async {
    await comoUsuario(_uidParticipante, () async {
      await expectLater(
        conn.execute(
          Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
          parameters: {'rodada': votingRoundId},
        ),
        throwsA(isA<ServerException>()),
      );
    });

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNull);
  });

  test('FR-009: o Dono do Grupo força fechamento antes do prazo', () async {
    await comoUsuario(_uidDono, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNotNull);
  });
}

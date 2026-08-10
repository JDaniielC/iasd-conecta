import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000027';
const _uidVotanteA = '70000000-0000-0000-0000-000000000028';
const _uidVotanteB = '70000000-0000-0000-0000-000000000029';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;
  late Object candidateA;
  late Object candidateB;

  Future<void> asUser(String uid, Future<void> Function() action) async {
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
    await createTestProfile(conn, _uidOwner, name: 'Dono ApuracaoEmpate');
    await createTestProfile(conn, _uidVotanteA, name: 'VotanteA ApuracaoEmpate');
    await createTestProfile(conn, _uidVotanteB, name: 'VotanteB ApuracaoEmpate');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoEmpate', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @a), (@grupo, @b)',
      ),
      parameters: {'grupo': groupId, 'a': _uidVotanteA, 'b': _uidVotanteB},
    );

    late Object votingRound;
    late Object candA;
    late Object candB;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRound = rows.single.toColumnMap()['id']!;

      final rowsA = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Empate A', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      candA = rowsA.single.toColumnMap()['id']!;

      final rowsB = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Empate B', now() + interval '6 days', 'Praça', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      candB = rowsB.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;
    candidateA = candA;
    candidateB = candB;

    // empate 1-1
    await asUser(_uidVotanteA, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteA, 'candidata': candidateA},
      );
    });
    await asUser(_uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteB, 'candidata': candidateB},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidVotanteA);
    await cleanUpTestUser(conn, _uidVotanteB);
    await conn.close();
  });

  test('FR-011/FR-012: empate 1-1 é resolvido por sorteio entre as empatadas', () async {
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final roundRows = await conn.execute(
      Sql.named('select vencedora_id from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    final winner = roundRows.single.toColumnMap()['vencedora_id'];

    expect([candidateA, candidateB], contains(winner));

    final restantes = await conn.execute(
      Sql.named('select id from public.acoes where rodada_id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(restantes, hasLength(1));
    expect(restantes.single.toColumnMap()['id'], winner);
  });
}

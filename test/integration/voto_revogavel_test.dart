import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000020';
const _uidVotante = '70000000-0000-0000-0000-000000000021';

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
    await createTestProfile(conn, _uidOwner, name: 'Dono VotoRevogavel');
    await createTestProfile(conn, _uidVotante, name: 'Votante VotoRevogavel');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo VotoRevogavel', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidVotante},
    );

    late Object votingRound;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRound = rows.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;

    await asUser(_uidOwner, () async {
      final rowsA = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata A', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRoundId},
      );
      candidateA = rowsA.single.toColumnMap()['id']!;

      final rowsB = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata B', now() + interval '6 days', 'Praca', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRoundId},
      );
      candidateB = rowsB.single.toColumnMap()['id']!;
    });
  });

  tearDownAll(() async {
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
    await cleanUpTestUser(conn, _uidVotante);
    await conn.close();
  });

  test('FR-006: trocar de candidata atualiza a mesma linha, só a última conta', () async {
    await asUser(_uidVotante, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata) '
          'on conflict (rodada_id, usuario_id) do update set candidata_id = excluded.candidata_id',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotante, 'candidata': candidateA},
      );
    });

    await asUser(_uidVotante, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata) '
          'on conflict (rodada_id, usuario_id) do update set candidata_id = excluded.candidata_id',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotante, 'candidata': candidateB},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select candidata_id from public.votos where rodada_id = @rodada and usuario_id = @usuario',
      ),
      parameters: {'rodada': votingRoundId, 'usuario': _uidVotante},
    );
    expect(rows, hasLength(1));
    expect(rows.single.toColumnMap()['candidata_id'], candidateB);
  });
}

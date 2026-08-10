import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000022';
const _uidOutsider = '70000000-0000-0000-0000-000000000023';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;
  late Object candidateId;

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
    await createTestProfile(conn, _uidOwner, name: 'Dono VotarParticipante');
    await createTestProfile(conn, _uidOutsider, name: 'ForaDoGrupo VotarParticipante');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo VotarParticipante', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    late Object votingRound;
    late Object candidate;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRound = rows.single.toColumnMap()['id']!;

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Única', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      candidate = candRows.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;
    candidateId = candidate;
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
    await cleanUpTestUser(conn, _uidOutsider);
    await conn.close();
  });

  test('FR-007: quem não participa do Grupo não vota', () async {
    await expectLater(
      asUser(_uidOutsider, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@rodada, @usuario, @candidata)',
          ),
          parameters: {'rodada': votingRoundId, 'usuario': _uidOutsider, 'candidata': candidateId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

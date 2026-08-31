import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000030';
const _uidVotanteA = '70000000-0000-0000-0000-000000000031';
const _uidVotanteB = '70000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;
  late Object leadingCandidate;
  late Object losingCandidate;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono ApuracaoVencedora');
    await createTestProfile(conn, _uidVotanteA, name: 'VotanteA ApuracaoVencedora');
    await createTestProfile(conn, _uidVotanteB, name: 'VotanteB ApuracaoVencedora');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoVencedora', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
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
    late Object lider;
    late Object perdedora;
    await asUser(conn, _uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRound = rows.single.toColumnMap()['id']!;

      final rowsLider = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Líder', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      lider = rowsLider.single.toColumnMap()['id']!;

      final rowsPerdedora = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Perdedora', now() + interval '6 days', 'Praça', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      perdedora = rowsPerdedora.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;
    leadingCandidate = lider;
    losingCandidate = perdedora;

    // Confirma presença na perdedora ANTES de fechar, pra provar que some junto.
    await asUser(conn, _uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
        ),
        parameters: {'acao': losingCandidate, 'usuario': _uidVotanteB},
      );
    });

    // 2 votos pra líder, 0 pra perdedora
    await asUser(conn, _uidVotanteA, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteA, 'candidata': leadingCandidate},
      );
    });
    await asUser(conn, _uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteB, 'candidata': leadingCandidate},
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

  test('FR-013/FR-014: vencedora vira confirmada, perdedora some com a presença', () async {
    await asUser(conn, _uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final roundRows = await conn.execute(
      Sql.named('select vencedora_id from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(roundRows.single.toColumnMap()['vencedora_id'], leadingCandidate);

    final liderRows = await conn.execute(
      Sql.named('select confirmada from public.acoes where id = @id'),
      parameters: {'id': leadingCandidate},
    );
    expect(liderRows.single.toColumnMap()['confirmada'], isTrue);

    final perdedoraRows = await conn.execute(
      Sql.named('select count(*) as total from public.acoes where id = @id'),
      parameters: {'id': losingCandidate},
    );
    expect(perdedoraRows.single.toColumnMap()['total'], 0);

    final losingConfirmations = await conn.execute(
      Sql.named(
        'select count(*) as total from public.confirmacoes_acao where acao_id = @id',
      ),
      parameters: {'id': losingCandidate},
    );
    expect(losingConfirmations.single.toColumnMap()['total'], 0);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000036';
const _uidConfirmado = '70000000-0000-0000-0000-000000000037';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;
  late Object winningCandidate;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono ApuracaoPresenca');
    await createTestProfile(conn, _uidConfirmado, name: 'Confirmado ApuracaoPresenca');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoPresenca', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidConfirmado},
    );

    late Object votingRound;
    late Object winner;
    await asUser(conn, _uidOwner, () async {
      final roundRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRound = roundRows.single.toColumnMap()['id']!;

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Única Candidata', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      winner = candRows.single.toColumnMap()['id']!;
    });
    votingRoundId = votingRound;
    winningCandidate = winner;

    // confirma presença ANTES de fechar
    await asUser(conn, _uidConfirmado, () async {
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
        ),
        parameters: {'acao': winningCandidate, 'usuario': _uidConfirmado},
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
    await cleanUpTestUser(conn, _uidConfirmado);
    await conn.close();
  });

  test('FR-013: presença confirmada antes de fechar sobrevive na vencedora', () async {
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
    expect(roundRows.single.toColumnMap()['vencedora_id'], winningCandidate);

    final confirmations = await conn.execute(
      Sql.named(
        'select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @usuario',
      ),
      parameters: {'acao': winningCandidate, 'usuario': _uidConfirmado},
    );
    expect(confirmations, hasLength(1));
    expect(confirmations.single.toColumnMap()['status'], 'confirmado');
  });
}

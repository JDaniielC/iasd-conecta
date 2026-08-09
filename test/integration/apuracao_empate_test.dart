import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000027';
const _uidVotanteA = '70000000-0000-0000-0000-000000000028';
const _uidVotanteB = '70000000-0000-0000-0000-000000000029';

void main() {
  late Connection conn;
  late Object grupoId;
  late Object votingRoundId;
  late Object candidataA;
  late Object candidataB;

  Future<void> comoUsuario(String uid, Future<void> Function() acao) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await acao();
    } finally {
      await conn.execute('reset role');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono ApuracaoEmpate');
    await criarPerfilDeTeste(conn, _uidVotanteA, nome: 'VotanteA ApuracaoEmpate');
    await criarPerfilDeTeste(conn, _uidVotanteB, nome: 'VotanteB ApuracaoEmpate');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoEmpate', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = grupoRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @a), (@grupo, @b)',
      ),
      parameters: {'grupo': grupoId, 'a': _uidVotanteA, 'b': _uidVotanteB},
    );

    late Object rodada;
    late Object candA;
    late Object candB;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodada = rows.single.toColumnMap()['id']!;

      final rowsA = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Empate A', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': rodada},
      );
      candA = rowsA.single.toColumnMap()['id']!;

      final rowsB = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Empate B', now() + interval '6 days', 'Praça', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': rodada},
      );
      candB = rowsB.single.toColumnMap()['id']!;
    });
    votingRoundId = rodada;
    candidataA = candA;
    candidataB = candB;

    // empate 1-1
    await comoUsuario(_uidVotanteA, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteA, 'candidata': candidataA},
      );
    });
    await comoUsuario(_uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteB, 'candidata': candidataB},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidVotanteA);
    await limparUsuarioDeTeste(conn, _uidVotanteB);
    await conn.close();
  });

  test('FR-011/FR-012: empate 1-1 é resolvido por sorteio entre as empatadas', () async {
    await comoUsuario(_uidDono, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final rodadaRows = await conn.execute(
      Sql.named('select vencedora_id from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    final vencedora = rodadaRows.single.toColumnMap()['vencedora_id'];

    expect([candidataA, candidataB], contains(vencedora));

    final restantes = await conn.execute(
      Sql.named('select id from public.acoes where rodada_id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(restantes, hasLength(1));
    expect(restantes.single.toColumnMap()['id'], vencedora);
  });
}

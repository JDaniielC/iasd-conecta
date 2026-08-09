import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000030';
const _uidVotanteA = '70000000-0000-0000-0000-000000000031';
const _uidVotanteB = '70000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late Object grupoId;
  late Object votingRoundId;
  late Object candidataLider;
  late Object candidataPerdedora;

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
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono ApuracaoVencedora');
    await criarPerfilDeTeste(conn, _uidVotanteA, nome: 'VotanteA ApuracaoVencedora');
    await criarPerfilDeTeste(conn, _uidVotanteB, nome: 'VotanteB ApuracaoVencedora');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoVencedora', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
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
    late Object lider;
    late Object perdedora;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodada = rows.single.toColumnMap()['id']!;

      final rowsLider = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Líder', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': rodada},
      );
      lider = rowsLider.single.toColumnMap()['id']!;

      final rowsPerdedora = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Perdedora', now() + interval '6 days', 'Praça', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': rodada},
      );
      perdedora = rowsPerdedora.single.toColumnMap()['id']!;
    });
    votingRoundId = rodada;
    candidataLider = lider;
    candidataPerdedora = perdedora;

    // Confirma presença na perdedora ANTES de fechar, pra provar que some junto.
    await comoUsuario(_uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
        ),
        parameters: {'acao': candidataPerdedora, 'usuario': _uidVotanteB},
      );
    });

    // 2 votos pra líder, 0 pra perdedora
    await comoUsuario(_uidVotanteA, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteA, 'candidata': candidataLider},
      );
    });
    await comoUsuario(_uidVotanteB, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotanteB, 'candidata': candidataLider},
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

  test('FR-013/FR-014: vencedora vira confirmada, perdedora some com a presença', () async {
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
    expect(rodadaRows.single.toColumnMap()['vencedora_id'], candidataLider);

    final liderRows = await conn.execute(
      Sql.named('select confirmada from public.acoes where id = @id'),
      parameters: {'id': candidataLider},
    );
    expect(liderRows.single.toColumnMap()['confirmada'], isTrue);

    final perdedoraRows = await conn.execute(
      Sql.named('select count(*) as total from public.acoes where id = @id'),
      parameters: {'id': candidataPerdedora},
    );
    expect(perdedoraRows.single.toColumnMap()['total'], 0);

    final confirmacoesPerdedora = await conn.execute(
      Sql.named(
        'select count(*) as total from public.confirmacoes_acao where acao_id = @id',
      ),
      parameters: {'id': candidataPerdedora},
    );
    expect(confirmacoesPerdedora.single.toColumnMap()['total'], 0);
  });
}

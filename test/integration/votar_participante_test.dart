import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000022';
const _uidForaDoGrupo = '70000000-0000-0000-0000-000000000023';

void main() {
  late Connection conn;
  late Object grupoId;
  late Object votingRoundId;
  late Object candidataId;

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
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono VotarParticipante');
    await criarPerfilDeTeste(conn, _uidForaDoGrupo, nome: 'ForaDoGrupo VotarParticipante');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo VotarParticipante', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = grupoRows.single.toColumnMap()['id']!;

    late Object rodada;
    late Object candidata;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodada = rows.single.toColumnMap()['id']!;

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Única', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': rodada},
      );
      candidata = candRows.single.toColumnMap()['id']!;
    });
    votingRoundId = rodada;
    candidataId = candidata;
  });

  tearDownAll(() async {
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
    await limparUsuarioDeTeste(conn, _uidForaDoGrupo);
    await conn.close();
  });

  test('FR-007: quem não participa do Grupo não vota', () async {
    await expectLater(
      comoUsuario(_uidForaDoGrupo, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@rodada, @usuario, @candidata)',
          ),
          parameters: {'rodada': votingRoundId, 'usuario': _uidForaDoGrupo, 'candidata': candidataId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000020';
const _uidVotante = '70000000-0000-0000-0000-000000000021';

void main() {
  late Connection conn;
  late Object groupId;
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
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono VotoRevogavel');
    await criarPerfilDeTeste(conn, _uidVotante, name: 'Votante VotoRevogavel');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo VotoRevogavel', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = grupoRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidVotante},
    );

    late Object rodada;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidDono},
      );
      rodada = rows.single.toColumnMap()['id']!;
    });
    votingRoundId = rodada;

    await comoUsuario(_uidDono, () async {
      final rowsA = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata A', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': votingRoundId},
      );
      candidataA = rowsA.single.toColumnMap()['id']!;

      final rowsB = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata B', now() + interval '6 days', 'Praca', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidDono, 'rodada': votingRoundId},
      );
      candidataB = rowsB.single.toColumnMap()['id']!;
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
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidVotante);
    await conn.close();
  });

  test('FR-006: trocar de candidata atualiza a mesma linha, só a última conta', () async {
    await comoUsuario(_uidVotante, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata) '
          'on conflict (rodada_id, usuario_id) do update set candidata_id = excluded.candidata_id',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotante, 'candidata': candidataA},
      );
    });

    await comoUsuario(_uidVotante, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata) '
          'on conflict (rodada_id, usuario_id) do update set candidata_id = excluded.candidata_id',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': _uidVotante, 'candidata': candidataB},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        'select candidata_id from public.votos where rodada_id = @rodada and usuario_id = @usuario',
      ),
      parameters: {'rodada': votingRoundId, 'usuario': _uidVotante},
    );
    expect(rows, hasLength(1));
    expect(rows.single.toColumnMap()['candidata_id'], candidataB);
  });
}

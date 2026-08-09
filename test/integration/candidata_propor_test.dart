import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000013';
const _uidParticipante = '70000000-0000-0000-0000-000000000014';
const _uidForaDoGrupo = '70000000-0000-0000-0000-000000000015';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono ProporCandidata');
    await criarPerfilDeTeste(conn, _uidParticipante, name: 'Participante ProporCandidata');
    await criarPerfilDeTeste(conn, _uidForaDoGrupo, name: 'ForaDoGrupo ProporCandidata');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ProporCandidata', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
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

    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$_uidDono\",\"role\":\"authenticated\"}'",
    );
    final rodadaRows = await conn.execute(
      Sql.named(
        "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
        "values (@grupo, @dono, now() + interval '1 day') returning id",
      ),
      parameters: {'grupo': groupId, 'dono': _uidDono},
    );
    votingRoundId = rodadaRows.single.toColumnMap()['id']!;
    await conn.execute('reset role');
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
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await limparUsuarioDeTeste(conn, _uidForaDoGrupo);
    await conn.close();
  });

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

  test('FR-004: quem não participa do Grupo não propõe candidata', () async {
    await expectLater(
      comoUsuario(_uidForaDoGrupo, () async {
        await conn.execute(
          Sql.named(
            "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
            "values ('Candidata Intrusa', now() + interval '5 days', 'Sede', @usuario, @rodada)",
          ),
          parameters: {'usuario': _uidForaDoGrupo, 'rodada': votingRoundId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-003: participante propõe candidata e grupo_id é derivado da Rodada', () async {
    await comoUsuario(_uidParticipante, () async {
      await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Válida', now() + interval '5 days', 'Sede', @usuario, @rodada)",
        ),
        parameters: {'usuario': _uidParticipante, 'rodada': votingRoundId},
      );
    });

    final rows = await conn.execute(
      Sql.named(
        "select grupo_id, confirmada from public.acoes "
        "where rodada_id = @rodada and nome = 'Candidata Válida'",
      ),
      parameters: {'rodada': votingRoundId},
    );
    final row = rows.single.toColumnMap();
    expect(row['grupo_id'], groupId);
    expect(row['confirmada'], isFalse);
  });
}

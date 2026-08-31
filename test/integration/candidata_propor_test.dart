import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000013';
const _uidMember = '70000000-0000-0000-0000-000000000014';
const _uidOutsider = '70000000-0000-0000-0000-000000000015';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono ProporCandidata');
    await createTestProfile(conn, _uidMember, name: 'Participante ProporCandidata');
    await createTestProfile(conn, _uidOutsider, name: 'ForaDoGrupo ProporCandidata');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ProporCandidata', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );

    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$_uidOwner\",\"role\":\"authenticated\"}'",
    );
    final roundRows = await conn.execute(
      Sql.named(
        "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
        "values (@grupo, @dono, now() + interval '1 day') returning id",
      ),
      parameters: {'grupo': groupId, 'dono': _uidOwner},
    );
    votingRoundId = roundRows.single.toColumnMap()['id']!;
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
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidMember);
    await cleanUpTestUser(conn, _uidOutsider);
    await conn.close();
  });

  test('FR-004: quem não participa do Grupo não propõe candidata', () async {
    await expectLater(
      asUser(conn, _uidOutsider, () async {
        await conn.execute(
          Sql.named(
            "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
            "values ('Candidata Intrusa', now() + interval '5 days', 'Sede', @usuario, @rodada)",
          ),
          parameters: {'usuario': _uidOutsider, 'rodada': votingRoundId},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-003: participante propõe candidata e grupo_id é derivado da Rodada', () async {
    await asUser(conn, _uidMember, () async {
      await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Válida', now() + interval '5 days', 'Sede', @usuario, @rodada)",
        ),
        parameters: {'usuario': _uidMember, 'rodada': votingRoundId},
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

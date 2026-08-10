import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000025';
const _uidMember = '70000000-0000-0000-0000-000000000026';

void main() {
  late Connection conn;
  late Object groupId;
  late Object votingRoundId;

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
    await createTestProfile(conn, _uidOwner, name: 'Dono ForcarFechamento');
    await createTestProfile(conn, _uidMember, name: 'Participante ForcarFechamento');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ForcarFechamento', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
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
  });

  tearDownAll(() async {
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
    await conn.close();
  });

  test('FR-010: participante que não é Dono não força fechamento', () async {
    await asUser(_uidMember, () async {
      await expectLater(
        conn.execute(
          Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
          parameters: {'rodada': votingRoundId},
        ),
        throwsA(isA<ServerException>()),
      );
    });

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNull);
  });

  test('FR-009: o Dono do Grupo força fechamento antes do prazo', () async {
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNotNull);
  });
}

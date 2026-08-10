import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000024';

void main() {
  late Connection conn;
  late Object groupId;

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
    await createTestProfile(conn, _uidOwner, name: 'Dono FechamentoPreguicoso');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo FechamentoPreguicoso', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;
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
    await conn.close();
  });

  test('FR-008: não fecha antes do prazo mesmo sem forçar', () async {
    late Object votingRoundId;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRoundId = rows.single.toColumnMap()['id']!;
    });

    await conn.execute(
      Sql.named('select public.fechar_rodada_se_devido(@rodada)'),
      parameters: {'rodada': votingRoundId},
    );

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNull);
  });

  test('FR-008: fecha (e apura sem candidata) quando o prazo já passou', () async {
    late Object votingRoundId;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() - interval '1 hour') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRoundId = rows.single.toColumnMap()['id']!;
    });

    await conn.execute(
      Sql.named('select public.fechar_rodada_se_devido(@rodada)'),
      parameters: {'rodada': votingRoundId},
    );

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNotNull);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000030';
const _uidCreator = '90000000-0000-0000-0000-000000000031';
const _uidGroupOwner = '90000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late Object standaloneActionId;
  late Object groupId;
  late Object groupActionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAdmin, name: 'Admin CancelAny');
    await createTestProfile(conn, _uidCreator, name: 'Criador CancelAny');
    await createTestProfile(conn, _uidGroupOwner, name: 'DonoGrupo CancelAny');
    await createTestDistrictAdmin(conn, _uidAdmin);

    late Object standaloneAction;
    await asUser(conn, _uidCreator, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id) "
          "values ('Ação Avulsa CancelAny', now() + interval '5 days', 'Sede', @criador) "
          "returning id",
        ),
        parameters: {'criador': _uidCreator},
      );
      standaloneAction = rows.single.toColumnMap()['id']!;
    });
    standaloneActionId = standaloneAction;

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo CancelAny', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidGroupOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    late Object groupAction;
    await asUser(conn, _uidGroupOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidGroupOwner},
      );
      final votingRoundId = rows.single.toColumnMap()['id'];

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Única Candidata CancelAny', now() + interval '5 days', 'Sede', @dono, @rodada) "
          "returning id",
        ),
        parameters: {'dono': _uidGroupOwner, 'rodada': votingRoundId},
      );
      groupAction = candRows.single.toColumnMap()['id']!;

      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });
    groupActionId = groupAction;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id in (@avulsa, @grupo)'),
      parameters: {'avulsa': standaloneActionId, 'grupo': groupActionId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await cleanUpTestUser(conn, _uidAdmin);
    await cleanUpTestUser(conn, _uidCreator);
    await cleanUpTestUser(conn, _uidGroupOwner);
    await conn.close();
  });

  test('FR-009: Administrador cancela Ação avulsa que não criou', () async {
    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @id'),
        parameters: {'id': standaloneActionId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @id'),
      parameters: {'id': standaloneActionId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });

  test('FR-009: Administrador cancela Ação de Grupo que não propôs nem administra', () async {
    await asUser(conn, _uidAdmin, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @id'),
        parameters: {'id': groupActionId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @id'),
      parameters: {'id': groupActionId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });
}

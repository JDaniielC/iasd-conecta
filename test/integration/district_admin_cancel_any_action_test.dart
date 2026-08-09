import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000030';
const _uidCriador = '90000000-0000-0000-0000-000000000031';
const _uidDonoGrupo = '90000000-0000-0000-0000-000000000032';

void main() {
  late Connection conn;
  late Object acaoAvulsaId;
  late Object groupId;
  late Object acaoDeGrupoId;

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAdmin, name: 'Admin CancelAny');
    await criarPerfilDeTeste(conn, _uidCriador, name: 'Criador CancelAny');
    await criarPerfilDeTeste(conn, _uidDonoGrupo, name: 'DonoGrupo CancelAny');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);

    late Object acaoAvulsa;
    await comoUsuario(_uidCriador, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id) "
          "values ('Ação Avulsa CancelAny', now() + interval '5 days', 'Sede', @criador) "
          "returning id",
        ),
        parameters: {'criador': _uidCriador},
      );
      acaoAvulsa = rows.single.toColumnMap()['id']!;
    });
    acaoAvulsaId = acaoAvulsa;

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo CancelAny', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDonoGrupo},
    );
    groupId = grupoRows.single.toColumnMap()['id']!;

    late Object acaoDeGrupo;
    await comoUsuario(_uidDonoGrupo, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidDonoGrupo},
      );
      final votingRoundId = rows.single.toColumnMap()['id'];

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Única Candidata CancelAny', now() + interval '5 days', 'Sede', @dono, @rodada) "
          "returning id",
        ),
        parameters: {'dono': _uidDonoGrupo, 'rodada': votingRoundId},
      );
      acaoDeGrupo = candRows.single.toColumnMap()['id']!;

      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });
    acaoDeGrupoId = acaoDeGrupo;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id in (@avulsa, @grupo)'),
      parameters: {'avulsa': acaoAvulsaId, 'grupo': acaoDeGrupoId},
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
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await limparUsuarioDeTeste(conn, _uidCriador);
    await limparUsuarioDeTeste(conn, _uidDonoGrupo);
    await conn.close();
  });

  test('FR-009: Administrador cancela Ação avulsa que não criou', () async {
    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @id'),
        parameters: {'id': acaoAvulsaId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @id'),
      parameters: {'id': acaoAvulsaId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });

  test('FR-009: Administrador cancela Ação de Grupo que não propôs nem administra', () async {
    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @id'),
        parameters: {'id': acaoDeGrupoId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @id'),
      parameters: {'id': acaoDeGrupoId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });
}

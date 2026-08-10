import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000038';
const _uidProponente = '70000000-0000-0000-0000-000000000039';
const _uidOtherMember = '70000000-0000-0000-0000-000000000040';

void main() {
  late Connection conn;
  late Object groupId;
  late Object confirmedActionId;

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
    await createTestProfile(conn, _uidOwner, name: 'Dono CancelarAcaoGrupo');
    await createTestProfile(conn, _uidProponente, name: 'Proponente CancelarAcaoGrupo');
    await createTestProfile(conn, _uidOtherMember, name: 'Outro CancelarAcaoGrupo');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo CancelarAcaoGrupo', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @a), (@grupo, @b)',
      ),
      parameters: {'grupo': groupId, 'a': _uidProponente, 'b': _uidOtherMember},
    );

    late Object actionId;
    late Object votingRoundId;
    await asUser(_uidProponente, () async {
      final roundRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @proponente, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'proponente': _uidProponente},
      );
      votingRoundId = roundRows.single.toColumnMap()['id']!;

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Única Candidata Cancelar', now() + interval '5 days', 'Sede', @proponente, @rodada) "
          "returning id",
        ),
        parameters: {'proponente': _uidProponente, 'rodada': votingRoundId},
      );
      actionId = candRows.single.toColumnMap()['id']!;
    });

    // fecha a rodada forçado pelo dono — a única candidata vira Ação de Grupo confirmada
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    confirmedActionId = actionId;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
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
    await cleanUpTestUser(conn, _uidProponente);
    await cleanUpTestUser(conn, _uidOtherMember);
    await conn.close();
  });

  test('participante que não é Dono nem propôs não consegue cancelar', () async {
    await asUser(_uidOtherMember, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': confirmedActionId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': confirmedActionId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNull);
  });

  test('FR-016: Dono do Grupo cancela mesmo sem ter proposto a vencedora', () async {
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': confirmedActionId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': confirmedActionId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });
}

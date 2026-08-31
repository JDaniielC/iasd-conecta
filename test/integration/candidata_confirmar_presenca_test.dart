import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000034';
const _uidMember = '70000000-0000-0000-0000-000000000035';

void main() {
  late Connection conn;
  late Object groupId;
  late Object candidateId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono ConfirmarCandidata');
    await createTestProfile(conn, _uidMember, name: 'Participante ConfirmarCandidata');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ConfirmarCandidata', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
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

    late Object candidate;
    await asUser(conn, _uidOwner, () async {
      final roundRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      final votingRound = roundRows.single.toColumnMap()['id'];

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata Confirmável', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRound},
      );
      candidate = candRows.single.toColumnMap()['id']!;
    });
    candidateId = candidate;
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
    await cleanUpTestUser(conn, _uidMember);
    await conn.close();
  });

  test('FR-015: confirmar presença numa candidata funciona igual Ação avulsa', () async {
    await asUser(conn, _uidMember, () async {
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
        ),
        parameters: {'acao': candidateId, 'usuario': _uidMember},
      );
    });

    final rows = await conn.execute(
      Sql.named('select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @usuario'),
      parameters: {'acao': candidateId, 'usuario': _uidMember},
    );
    expect(rows.single.toColumnMap()['status'], 'confirmado');
  });
}

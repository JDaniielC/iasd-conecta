import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '95000000-0000-0000-0000-000000000020';

void main() {
  late Connection conn;
  late String groupId;
  late String votingRoundId;
  late String candidateId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono ProtegeCampos');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ProtegeCampos', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']! as String;

    await asUser(conn, _uidOwner, () async {
      final roundRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '7 days') returning id",
        ),
        parameters: {'grupo': groupId, 'dono': _uidOwner},
      );
      votingRoundId = roundRows.single.toColumnMap()['id']! as String;

      final candidateRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Candidata ProtegeCampos', now() + interval '5 days', 'Sede', @dono, @rodada) "
          "returning id",
        ),
        parameters: {'dono': _uidOwner, 'rodada': votingRoundId},
      );
      candidateId = candidateRows.single.toColumnMap()['id']! as String;
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.votos where rodada_id = @id'),
      parameters: {'id': votingRoundId},
    );
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where id = @id'),
      parameters: {'id': votingRoundId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @id'),
      parameters: {'id': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where id = @id'),
      parameters: {'id': votingRoundId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await conn.close();
  });

  test(
    'BUG DE SEGURANÇA (corrigido): criador não consegue auto-confirmar a própria '
    'candidata via UPDATE direto, bypassando a apuração',
    () async {
      await expectLater(
        asUser(conn, _uidOwner, () async {
          await conn.execute(
            Sql.named('update public.acoes set confirmada = true where id = @id'),
            parameters: {'id': candidateId},
          );
        }),
        throwsA(isA<ServerException>()),
      );
    },
  );

  test(
    'fechar_rodada_se_devido (caminho interno legítimo) ainda consegue confirmar a vencedora',
    () async {
      await asUser(conn, _uidOwner, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@rodada, @dono, @candidata)',
          ),
          parameters: {'rodada': votingRoundId, 'dono': _uidOwner, 'candidata': candidateId},
        );
        await conn.execute(
          Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
          parameters: {'rodada': votingRoundId},
        );
      });

      final rows = await conn.execute(
        Sql.named('select confirmada from public.acoes where id = @id'),
        parameters: {'id': candidateId},
      );
      expect(rows.single.toColumnMap()['confirmada'], isTrue);
    },
  );
}

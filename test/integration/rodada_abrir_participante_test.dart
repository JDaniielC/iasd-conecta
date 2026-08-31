import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

const _uidOwner = '70000000-0000-0000-0000-000000000010';
const _uidMember = '70000000-0000-0000-0000-000000000011';
const _uidOutsider = '70000000-0000-0000-0000-000000000012';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono AbrirRodada');
    await createTestProfile(conn, _uidMember, name: 'Participante AbrirRodada');
    await createTestProfile(conn, _uidOutsider, name: 'ForaDoGrupo AbrirRodada');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo AbrirRodada', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidMember},
    );
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
    await cleanUpTestUser(conn, _uidOutsider);
    await conn.close();
  });

  test('FR-004: quem não participa do Grupo não abre Rodada', () async {
    await expectLater(
      asUser(conn, _uidOutsider, () async {
        await conn.execute(
          Sql.named(
            "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
            "values (@grupo, @usuario, now() + interval '1 day')",
          ),
          parameters: {'grupo': groupId, 'usuario': _uidOutsider},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('participante do Grupo abre Rodada normalmente', () async {
    await asUser(conn, _uidMember, () async {
      await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @usuario, now() + interval '1 day')",
        ),
        parameters: {'grupo': groupId, 'usuario': _uidMember},
      );
    });

    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}

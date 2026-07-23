import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000009';
const _uidParticipante = '40000000-0000-0000-0000-000000000010';

void main() {
  late Connection conn;
  late Object grupoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono Sai');
    await criarPerfilDeTeste(conn, _uidParticipante, nome: 'Participante Sai');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Sai', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await conn.close();
  });

  test('FR-012: Dono não sai do grupo sem transferir a posse antes', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @dono',
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('participante comum (não Dono) sai livremente', () async {
    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @usuario',
      ),
      parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
    );
    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @usuario',
      ),
      parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });

  test('Dono sai depois de transferir a posse', () async {
    // recoloca o participante pra poder transferir de novo
    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario) '
        'on conflict (grupo_id, usuario_id) do nothing',
      ),
      parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
    );
    await conn.execute(
      Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
      parameters: {'novo': _uidParticipante, 'grupo': grupoId},
    );

    await conn.execute(
      Sql.named(
        'delete from public.participacoes_grupo where grupo_id = @grupo and usuario_id = @antigo',
      ),
      parameters: {'grupo': grupoId, 'antigo': _uidDono},
    );

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @antigo',
      ),
      parameters: {'grupo': grupoId, 'antigo': _uidDono},
    );
    expect(rows.single.toColumnMap()['total'], 0);
  });
}

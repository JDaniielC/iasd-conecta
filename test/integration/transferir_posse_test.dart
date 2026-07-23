import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000006';
const _uidNaoParticipante = '40000000-0000-0000-0000-000000000007';
const _uidParticipante = '40000000-0000-0000-0000-000000000008';

void main() {
  late Connection conn;
  late Object grupoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono Transfere');
    await criarPerfilDeTeste(conn, _uidNaoParticipante, nome: 'Fora do Grupo');
    await criarPerfilDeTeste(conn, _uidParticipante, nome: 'Participante Transfere');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Transfere', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
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
    await limparUsuarioDeTeste(conn, _uidNaoParticipante);
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await conn.close();
  });

  test('FR-011: transferir pra quem não participa falha', () async {
    await expectLater(
      conn.execute(
        Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
        parameters: {'novo': _uidNaoParticipante, 'grupo': grupoId},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('FR-011: transferir pra quem já participa funciona', () async {
    await conn.execute(
      Sql.named('update public.grupos set dono_id = @novo where id = @grupo'),
      parameters: {'novo': _uidParticipante, 'grupo': grupoId},
    );
    final rows = await conn.execute(
      Sql.named('select dono_id from public.grupos where id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    expect(rows.single.toColumnMap()['dono_id'], _uidParticipante);
  });
}

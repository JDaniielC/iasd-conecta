import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000004';
const _uidParticipante = '40000000-0000-0000-0000-000000000005';

void main() {
  late Connection conn;
  late Object groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono Idem');
    await criarPerfilDeTeste(conn, _uidParticipante, name: 'Participante Idem');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo Idem', 'Ministério Jovem', '19h', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidDono},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await conn.close();
  });

  test('FR-013: participar duas vezes não duplica nem falha', () async {
    Future<void> join() => conn.execute(
          Sql.named(
            'insert into public.participacoes_grupo (grupo_id, usuario_id) '
            'values (@grupo, @usuario) on conflict (grupo_id, usuario_id) do nothing',
          ),
          parameters: {'grupo': groupId, 'usuario': _uidParticipante},
        );

    await join();
    await join();

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.participacoes_grupo '
        'where grupo_id = @grupo and usuario_id = @usuario',
      ),
      parameters: {'grupo': groupId, 'usuario': _uidParticipante},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}

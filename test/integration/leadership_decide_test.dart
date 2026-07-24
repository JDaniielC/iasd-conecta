import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000040';
const _uidLider = '90000000-0000-0000-0000-000000000041';

void main() {
  late Connection conn;
  late String grupoId;
  late String liderancaId;

  Future<void> comoUsuario(String uid, Future<void> Function() acao) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await acao();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAdmin, nome: 'Admin Decide');
    await criarPerfilDeTeste(conn, _uidLider, nome: 'Lider Decide');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);
    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipDecide', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidAdmin},
    );
    grupoId = grupoRows.single.toColumnMap()['id']! as String;
    final liderancaRows = await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano) '
        'values (@grupo, @uid, 2026) returning id',
      ),
      parameters: {'grupo': grupoId, 'uid': _uidLider},
    );
    liderancaId = liderancaRows.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.liderancas where grupo_id = @id'),
      parameters: {'id': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidAdmin},
    );
    await limparUsuarioDeTeste(conn, _uidAdmin);
    await limparUsuarioDeTeste(conn, _uidLider);
    await conn.close();
  });

  test('FR-004: Administrador confirma e rejeita corretamente', () async {
    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, true)'),
        parameters: {'id': liderancaId},
      );
    });
    var row = (await conn.execute(
      Sql.named(
        'select confirmado_em, confirmado_por, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': liderancaId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNotNull);
    expect(row['confirmado_por'], _uidAdmin);
    expect(row['rejeitado_em'], isNull);

    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, false)'),
        parameters: {'id': liderancaId},
      );
    });
    row = (await conn.execute(
      Sql.named(
        'select confirmado_em, confirmado_por, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': liderancaId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNull);
    expect(row['confirmado_por'], isNull);
    expect(row['rejeitado_em'], isNotNull);
  });
}

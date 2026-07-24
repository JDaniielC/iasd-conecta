import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAdmin = '90000000-0000-0000-0000-000000000070';
const _uidLider = '90000000-0000-0000-0000-000000000071';

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
    await criarPerfilDeTeste(conn, _uidAdmin, nome: 'Admin RedeclareAfterReject');
    await criarPerfilDeTeste(conn, _uidLider, nome: 'Lider RedeclareAfterReject');
    await criarAdministradorDistritoDeTeste(conn, _uidAdmin);
    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo LeadershipRedeclareAfterReject', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidAdmin},
    );
    grupoId = grupoRows.single.toColumnMap()['id']! as String;

    await comoUsuario(_uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': grupoId},
      );
    });
    final row = await conn.execute(
      Sql.named(
        'select id from public.liderancas where grupo_id = @grupo and usuario_id = @uid and ano = 2026',
      ),
      parameters: {'grupo': grupoId, 'uid': _uidLider},
    );
    liderancaId = row.single.toColumnMap()['id']! as String;

    await comoUsuario(_uidAdmin, () async {
      await conn.execute(
        Sql.named('select public.decidir_lideranca(@id, false)'),
        parameters: {'id': liderancaId},
      );
    });
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

  test('FR-010: redeclarar depois de rejeitado no mesmo ano volta a ficar pendente', () async {
    var row = (await conn.execute(
      Sql.named('select rejeitado_em from public.liderancas where id = @id'),
      parameters: {'id': liderancaId},
    ))
        .single
        .toColumnMap();
    expect(row['rejeitado_em'], isNotNull);

    await comoUsuario(_uidLider, () async {
      await conn.execute(
        Sql.named('select public.declarar_lideranca(@grupo, 2026)'),
        parameters: {'grupo': grupoId},
      );
    });

    row = (await conn.execute(
      Sql.named(
        'select confirmado_em, rejeitado_em from public.liderancas where id = @id',
      ),
      parameters: {'id': liderancaId},
    ))
        .single
        .toColumnMap();
    expect(row['confirmado_em'], isNull);
    expect(row['rejeitado_em'], isNull);
  });
}

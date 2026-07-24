import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidAtacante = '95000000-0000-0000-0000-000000000010';
const _uidDono = '95000000-0000-0000-0000-000000000011';

void main() {
  late Connection conn;
  late String grupoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidAtacante, nome: 'Atacante SemRodada');
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono SemRodada');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo SemRodada', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = rows.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @id'),
      parameters: {'id': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @id'),
      parameters: {'id': grupoId},
    );
    await limparUsuarioDeTeste(conn, _uidAtacante);
    await limparUsuarioDeTeste(conn, _uidDono);
    await conn.close();
  });

  test(
    'BUG DE SEGURANÇA (corrigido): não dá pra forjar Ação de Grupo confirmada com '
    'grupo_id preenchido e rodada_id nulo, sem nunca ter participado do Grupo',
    () async {
      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uidAtacante\",\"role\":\"authenticated\"}'",
      );
      try {
        await expectLater(
          conn.execute(
            Sql.named(
              "insert into public.acoes (nome, data_hora, local, criador_id, grupo_id) "
              "values ('Forjada', now() + interval '1 day', 'X', @uid, @grupo)",
            ),
            parameters: {'uid': _uidAtacante, 'grupo': grupoId},
          ),
          throwsA(isA<ServerException>()),
        );
      } finally {
        await conn.execute('reset role');
        await conn.execute('reset request.jwt.claims');
      }
    },
  );
}

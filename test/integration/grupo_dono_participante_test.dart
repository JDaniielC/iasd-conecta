import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '40000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarPerfilDeTeste(conn, _uidDono, nome: 'Dono Auto'));
  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = @dono'),
      parameters: {'dono': _uidDono},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
  });

  test(
    'FR-003: criar grupo insere automaticamente participação do dono',
    () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.grupos (nome, categoria, horario, local, dono_id) "
          "values ('Coral', 'Ministério da Música', 'quartas 19h', 'Sede', @dono) "
          "returning id",
        ),
        parameters: {'dono': _uidDono},
      );
      final grupoId = rows.single.toColumnMap()['id'];

      final participacoes = await conn.execute(
        Sql.named(
          'select usuario_id from public.participacoes_grupo where grupo_id = @grupo',
        ),
        parameters: {'grupo': grupoId},
      );

      expect(participacoes, hasLength(1));
      expect(participacoes.single.toColumnMap()['usuario_id'], _uidDono);
    },
  );
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uid = '10000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() async {
    await conn.close();
  });

  setUp(() => criarUsuarioDeTeste(conn, _uid));
  tearDown(() => limparUsuarioDeTeste(conn, _uid));

  test('FR-003: insert em perfis sem consentimento LGPD falha', () async {
    await expectLater(
      conn.execute(
        Sql.named(
          "insert into public.perfis (id, nome, genero, idade) "
          "values (@id, 'Ana Souza', 'feminino', 30)",
        ),
        parameters: {'id': _uid},
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('cadastro válido (adulto, sem Igreja/telefone) é aceito', () async {
    await conn.execute(
      Sql.named(
        "insert into public.perfis "
        "(id, nome, genero, idade, consentimento_lgpd_aceito_em) "
        "values (@id, 'Ana Souza', 'feminino', 30, now())",
      ),
      parameters: {'id': _uid},
    );

    final rows = await conn.execute(
      Sql.named('select nome from public.perfis where id = @id'),
      parameters: {'id': _uid},
    );
    expect(rows.single.toColumnMap()['nome'], 'Ana Souza');
  });

  group('consentimento_igreja_destacado (LGPD art. 11 I)', () {
    late String igrejaId;

    setUp(() async {
      final rows = await conn.execute(
        Sql.named("insert into public.igrejas (nome) values ('Igreja ConsentimentoTeste') returning id"),
      );
      igrejaId = rows.single.toColumnMap()['id']! as String;
    });

    tearDown(() async {
      // Apaga o perfil primeiro — senão a FK perfis_igreja_id_fkey bloqueia
      // apagar a igreja enquanto o perfil de teste ainda a referencia.
      await conn.execute(
        Sql.named('delete from public.perfis where id = @id'),
        parameters: {'id': _uid},
      );
      await conn.execute(
        Sql.named('delete from public.igrejas where id = @id'),
        parameters: {'id': igrejaId},
      );
    });

    test('igreja_id preenchido sem consentimento destacado falha', () async {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.perfis "
            "(id, nome, genero, idade, consentimento_lgpd_aceito_em, igreja_id) "
            "values (@id, 'Ana Souza', 'feminino', 30, now(), @igreja)",
          ),
          parameters: {'id': _uid, 'igreja': igrejaId},
        ),
        throwsA(isA<ServerException>()),
      );
    });

    test('igreja_id preenchido com consentimento destacado é aceito', () async {
      await conn.execute(
        Sql.named(
          "insert into public.perfis "
          "(id, nome, genero, idade, consentimento_lgpd_aceito_em, igreja_id, "
          "consentimento_lgpd_igreja_aceito_em) "
          "values (@id, 'Ana Souza', 'feminino', 30, now(), @igreja, now())",
        ),
        parameters: {'id': _uid, 'igreja': igrejaId},
      );

      final rows = await conn.execute(
        Sql.named('select igreja_id from public.perfis where id = @id'),
        parameters: {'id': _uid},
      );
      expect(rows.single.toColumnMap()['igreja_id'], igrejaId);
    });
  });
}

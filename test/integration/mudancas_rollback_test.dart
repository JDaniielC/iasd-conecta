import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — falha ao registrar desfaz a
/// operação que a originou.
///
/// O requisito tem cenário próprio e não tinha teste: a task só mandava
/// CONFERIR que as funções não capturam exceção. Ler o código não é observar o
/// comportamento, e é justamente isso que este repositório já pagou caro para
/// aprender.
///
/// A quebra é montada de dentro: uma constraint impossível em `mudancas`, dentro
/// da transação do teste, faz a gravação do registro falhar. O que se observa é
/// se a alteração da Ação sobreviveu — e ela não pode sobreviver. Registro com
/// buraco é pior que operação recusada, porque quem lê passa a confiar num
/// histórico incompleto sem nenhum sinal de que está incompleto.

const _uidDona = 'e3000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona E3');
    actionId = await createLooseAction(conn, creatorId: _uidDona, name: 'Ação E3');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.mudancas where acao_id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    await cleanUpTestUser(conn, _uidDona);
    await conn.close();
  });

  test('com a gravação do registro quebrada, a alteração da Ação não é aplicada',
      () async {
    final antes = await conn.execute(
      Sql.named('select local from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    expect(antes.single.toColumnMap()['local'], 'Sede');

    await conn.execute('begin');
    try {
      await conn.execute(
        'alter table public.mudancas add constraint tmp_falha_teste check (false) not valid',
      );
      await conn.execute('savepoint antes_do_update');

      Object? erro;
      try {
        await conn.execute(
          Sql.named("update public.acoes set local = 'Praça' where id = @a"),
          parameters: {'a': actionId},
        );
      } catch (e) {
        erro = e;
      }
      expect(erro, isA<ServerException>(),
          reason: 'quem tentou recebe erro, não sucesso silencioso');

      await conn.execute('rollback to savepoint antes_do_update');
      final depois = await conn.execute(
        Sql.named('select local from public.acoes where id = @a'),
        parameters: {'a': actionId},
      );
      expect(depois.single.toColumnMap()['local'], 'Sede',
          reason: 'a alteração da Ação voltou atrás junto com o registro');
    } finally {
      await conn.execute('rollback');
    }
  });
}

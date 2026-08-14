import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — convidar exige Conta; receber, não.
///
/// A regra vive em `convidar_para_acao`, não numa policy, porque ela lê
/// `auth.users.is_anonymous` — fora do alcance de qualquer policy. Mesmo
/// precedente de `declarar_lideranca`
/// (`20260724100000_leadership.sql:26-31`).
///
/// O segundo caso é o que impede a regra de ser aplicada larga demais: quem
/// tem Perfil anônimo continua RECEBENDO convite normalmente. Fechar os dois
/// lados de uma vez seria fácil e errado — deixaria de fora justamente quem
/// ainda não criou Conta, que é quem mais precisa ser chamado.

const _uidComConta = 'c3000000-0000-0000-0000-000000000001';
const _uidAnonimo = 'c3000000-0000-0000-0000-000000000002';
const _allUids = [_uidComConta, _uidAnonimo];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidComConta, name: 'Com Conta C3');
    await createTestProfileWithoutAccount(conn, _uidAnonimo,
        name: 'Sem Conta C3');

    groupId = await createGroup(conn, ownerId: _uidComConta, name: 'Grupo C3');
    await joinGroup(conn, groupId, _uidAnonimo);
    actionId =
        await createLooseAction(conn, creatorId: _uidComConta, name: 'Ação C3');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.convites_acao where acao_id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('Perfil anônimo é recusado ao convidar, pela API', () async {
    await expectLater(
      asUser(
        conn,
        _uidAnonimo,
        () => convidarParaAcao(conn,
            actionId: actionId, groupId: groupId, invitees: [_uidComConta]),
      ),
      throwsA(isA<ServerException>()),
    );
    expect(await convitesGravados(conn, actionId), isEmpty);
  });

  test('quem tem Conta convida, e quem tem Perfil anônimo é convidável',
      () async {
    final r = await asUser(
      conn,
      _uidComConta,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: groupId, invitees: [_uidAnonimo]),
    );
    expect(r[_uidAnonimo], 'criado');

    final gravados = await convitesGravados(conn, actionId);
    expect(gravados, hasLength(1));
    expect(gravados.single['convidado_id'], _uidAnonimo);
    expect(gravados.single['convidante_id'], _uidComConta);
  });

  test('quem foi convidado lê o próprio convite, mesmo sem Conta', () async {
    final r = await asUser(conn, _uidAnonimo, () async {
      final rows = await conn.execute(
        Sql.named('select grupo_id::text from public.convites_acao where acao_id = @a'),
        parameters: {'a': actionId},
      );
      return rows.map((x) => x.toColumnMap()['grupo_id']).toList();
    });
    expect(r, [groupId]);
  });
}

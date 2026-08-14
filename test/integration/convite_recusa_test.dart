import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — recusar é da pessoa convidada, e só a coluna
/// `recusado_em`.
///
/// Criar convite não tem grant e passa por RPC, porque "quem convida tem Conta"
/// exige ler `auth.users`. Recusar é o oposto: a própria pessoa, sobre a própria
/// linha, sem nada fora do alcance de uma policy. Então sai por
/// `grant update (recusado_em)` + `convites_acao_update_convidado`.
///
/// O recorte por coluna é o que este arquivo prova junto com a policy. A lição
/// vem de `20260811160000_grant_update_perfis_por_coluna.sql`: lá a policy
/// protegia a LINHA e o grant não recortava a COLUNA, e dava para forjar a
/// própria `idade`. Aqui a policy diz quem, e o grant diz o quê.

const _uidConvidante = 'ca000000-0000-0000-0000-000000000001';
const _uidConvidada = 'ca000000-0000-0000-0000-000000000002';
const _uidTerceiro = 'ca000000-0000-0000-0000-000000000003';
const _allUids = [_uidConvidante, _uidConvidada, _uidTerceiro];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  Future<Object?> recusadoEm() async {
    final r = await conn.execute(
      Sql.named(
          'select recusado_em from public.convites_acao where acao_id = @a and convidado_id = @u'),
      parameters: {'a': actionId, 'u': _uidConvidada},
    );
    return r.single.toColumnMap()['recusado_em'];
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    groupId = await createGroup(conn, ownerId: _uidConvidante, name: 'Grupo CA');
    await joinGroup(conn, groupId, _uidConvidada);
    await joinGroup(conn, groupId, _uidTerceiro);
    actionId =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Ação CA');
    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: groupId, invitees: [_uidConvidada]),
    );
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

  test('terceiro não recusa convite alheio, e não recebe erro', () async {
    final afetadas = await asUser(conn, _uidTerceiro, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.convites_acao set recusado_em = now() where acao_id = @a'),
        parameters: {'a': actionId},
      );
      return r.affectedRows;
    });
    expect(afetadas, 0);
    expect(await recusadoEm(), isNull);
  });

  test('quem convidou não retira o convite', () async {
    final afetadas = await asUser(conn, _uidConvidante, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.convites_acao set recusado_em = now() where acao_id = @a'),
        parameters: {'a': actionId},
      );
      return r.affectedRows;
    });
    expect(afetadas, 0, reason: 'a policy de update é só do convidado');
    expect(await recusadoEm(), isNull);
  });

  test('a pessoa convidada recusa o próprio convite', () async {
    final afetadas = await asUser(conn, _uidConvidada, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.convites_acao set recusado_em = now() where acao_id = @a'),
        parameters: {'a': actionId},
      );
      return r.affectedRows;
    });
    expect(afetadas, 1);
    expect(await recusadoEm(), isNotNull);
  });

  test('a pessoa convidada não consegue mexer em outra coluna', () async {
    // Privilégio de coluna, não policy: a recusa vem antes de qualquer regra de
    // linha, com SQLSTATE 42501.
    await expectLater(
      asUser(conn, _uidConvidada, () async {
        await conn.execute(
          Sql.named(
              'update public.convites_acao set convidante_id = @u where acao_id = @a'),
          parameters: {'a': actionId, 'u': _uidConvidada},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — o lote classifica cada pessoa em vez de
/// estourar na primeira.
///
/// `RETURNING` sozinho não serviria: com `on conflict do nothing`, quem já
/// tinha sido convidado não volta no RETURNING, e a tela leria a ausência como
/// falha — mostrando erro para uma operação que deu certo. Por isso a função
/// devolve UMA LINHA POR PESSOA PEDIDA.

const _uidConvidante = 'c6000000-0000-0000-0000-000000000001';
const _uidNova = 'c6000000-0000-0000-0000-000000000002';
const _uidJaConvidada = 'c6000000-0000-0000-0000-000000000003';
const _uidDeFora = 'c6000000-0000-0000-0000-000000000004';
const _allUids = [_uidConvidante, _uidNova, _uidJaConvidada, _uidDeFora];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    groupId = await createGroup(conn, ownerId: _uidConvidante, name: 'Grupo C6');
    await joinGroup(conn, groupId, _uidNova);
    await joinGroup(conn, groupId, _uidJaConvidada);
    // _uidDeFora fica de fora do Grupo de propósito.
    actionId =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Ação C6');

    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: groupId, invitees: [_uidJaConvidada]),
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

  test('as três classificações voltam na mesma chamada', () async {
    final r = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn, actionId: actionId, groupId: groupId,
          invitees: [_uidNova, _uidJaConvidada, _uidDeFora]),
    );

    expect(r, hasLength(3), reason: 'uma linha por pessoa PEDIDA');
    expect(r[_uidNova], 'criado');
    expect(r[_uidJaConvidada], 'ja_convidado');
    expect(r[_uidDeFora], 'nao_participa');
  });

  test('a pessoa válida do lote ficou gravada, e quem é de fora não', () async {
    final gravados = await convitesGravados(conn, actionId);
    final ids = gravados.map((g) => g['convidado_id']).toSet();
    expect(ids, {_uidNova, _uidJaConvidada});
    expect(ids, isNot(contains(_uidDeFora)));
  });

  test('quem já era convidado não virou linha duplicada', () async {
    final gravados = await convitesGravados(conn, actionId);
    expect(
      gravados.where((g) => g['convidado_id'] == _uidJaConvidada),
      hasLength(1),
    );
  });
}

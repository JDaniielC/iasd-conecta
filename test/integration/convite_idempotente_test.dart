import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — o Grupo está na chave primária, e isso decide
/// o que duplica e o que não duplica.
///
/// Pelo mesmo Grupo, convidar de novo é idempotente e NÃO é erro: quem apertou
/// duas vezes não fez nada de errado. Por outro Grupo, é outro convite —
/// porque é por ele que a pessoa convidada filtra, e é ele que aparece como
/// explicação de origem.

const _uidConvidante = 'c7000000-0000-0000-0000-000000000001';
const _uidConvidada = 'c7000000-0000-0000-0000-000000000002';
const _allUids = [_uidConvidante, _uidConvidada];

void main() {
  late Connection conn;
  late String jovens, musica;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    jovens = await createGroup(conn, ownerId: _uidConvidante, name: 'Jovens C7');
    musica = await createGroup(conn, ownerId: _uidConvidante, name: 'Musica C7');
    await joinGroup(conn, jovens, _uidConvidada);
    await joinGroup(conn, musica, _uidConvidada);
    actionId =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Ação C7');
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
    for (final g in [jovens, musica]) {
      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': g},
      );
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('convidar duas vezes pelo mesmo Grupo dá uma linha, sem erro', () async {
    final primeira = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: jovens, invitees: [_uidConvidada]),
    );
    expect(primeira[_uidConvidada], 'criado');

    final segunda = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: jovens, invitees: [_uidConvidada]),
    );
    expect(segunda[_uidConvidada], 'ja_convidado',
        reason: 'repetir não é erro, e a tela não pode ler isso como falha');

    final gravados = await convitesGravados(conn, actionId);
    expect(gravados, hasLength(1));
  });

  test('a mesma pessoa pela mesma Ação por dois Grupos dá dois convites',
      () async {
    final r = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: musica, invitees: [_uidConvidada]),
    );
    expect(r[_uidConvidada], 'criado');

    final gravados = await convitesGravados(conn, actionId);
    expect(gravados, hasLength(2));
    expect(gravados.map((g) => g['grupo_id']).toSet(), {jovens, musica});
    // Os dois apontam para a mesma Ação — é o mesmo encontro, vindo por dois
    // caminhos.
    expect(gravados.map((g) => g['convidado_id']).toSet(), {_uidConvidada});
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — convite é das duas partes, de mais ninguém.
///
/// Convite recusado ou ignorado é informação da pessoa, não do grupo: a lista
/// de quem foi convidado não aparece na tela pública da Ação. A garantia é
/// `convites_acao_select_partes`, e a resposta para terceiro é CONJUNTO VAZIO,
/// não erro — `authenticated` tem `grant select`, então quem não é parte
/// simplesmente não vê linha.

const _uidConvidante = 'c5000000-0000-0000-0000-000000000001';
const _uidConvidada = 'c5000000-0000-0000-0000-000000000002';
const _uidTerceiro = 'c5000000-0000-0000-0000-000000000003';
const _allUids = [_uidConvidante, _uidConvidada, _uidTerceiro];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  Future<int> convitesVisiveis() async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.convites_acao where acao_id = @a'),
      parameters: {'a': actionId},
    );
    return r.first[0]! as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    groupId = await createGroup(conn, ownerId: _uidConvidante, name: 'Grupo C5');
    await joinGroup(conn, groupId, _uidConvidada);
    await joinGroup(conn, groupId, _uidTerceiro);
    actionId =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Ação C5');

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

  test('terceiro do mesmo Grupo recebe conjunto vazio, não erro', () async {
    expect(await asUser(conn, _uidTerceiro, convitesVisiveis), 0);
  });

  test('quem convidou vê o convite que fez', () async {
    expect(await asUser(conn, _uidConvidante, convitesVisiveis), 1);
  });

  test('quem foi convidada vê o convite que recebeu', () async {
    expect(await asUser(conn, _uidConvidada, convitesVisiveis), 1);
  });

  test('sessão anônima não lê convite nenhum', () async {
    // `anon` não tem nem `grant select` na tabela — convite não é público.
    await expectLater(
      asVisitor(conn, convitesVisiveis),
      throwsA(isA<ServerException>()),
    );
  });
}

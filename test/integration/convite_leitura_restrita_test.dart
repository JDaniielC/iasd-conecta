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

/// Visitante: pessoa sem cadastro, e por isso sem linha em `perfis`. TEM
/// sessão — `signInAnonymously` no arranque do app.
const _uidVisitor = 'c5000000-0000-0000-0000-0000000000f0';
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
      await createTestProfile(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
      );
    }
    await createTestVisitor(conn, _uidVisitor);
    groupId = await createGroup(
      conn,
      ownerId: _uidConvidante,
      name: 'Grupo C5',
    );
    await joinGroup(conn, groupId, _uidConvidada);
    await joinGroup(conn, groupId, _uidTerceiro);
    actionId = await createLooseAction(
      conn,
      creatorId: _uidConvidante,
      name: 'Ação C5',
    );

    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(
        conn,
        actionId: actionId,
        groupId: groupId,
        invitees: [_uidConvidada],
      ),
    );
  });

  tearDownAll(() async {
    await cleanUpTestUser(conn, _uidVisitor);
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

  test('Visitante sem cadastro lê ZERO convites — a policy filtra', () async {
    // A REGRA, e ela não tinha prova nenhuma até 2026-08-16. O teste abaixo
    // provava só o privilégio: sob `anon` a consulta para no `grant`, uma
    // camada antes da policy que decide quem vê convite.
    //
    // Medido: o Visitante ALCANÇA `convites_acao` e recebe 0 linhas. Ausência,
    // não erro — que é a forma certa de esconder, porque erro é contável.
    expect(await asVisitor(conn, _uidVisitor, convitesVisiveis), 0);
  });

  test('sem sessão nenhuma, a consulta nem alcança a tabela', () async {
    // Barreira DIFERENTE da de cima, e por isso teste separado: `anon` não tem
    // nem `grant select`. Não é a policy dizendo não — é o privilégio.
    // Afrouxar o grant faz este teste virar "0 linhas" em vez de exceção, e é
    // esse o sinal.
    await expectLater(
      asAnon(conn, convitesVisiveis),
      throwsA(isA<ServerException>()),
    );
  });
}

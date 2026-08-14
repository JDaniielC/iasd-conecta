import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — o convite APONTA, não reserva.
///
/// É o requisito que justifica não haver coluna de aceite: aceitar é confirmar
/// presença, e quem decide `confirmado` vs `fila` continua sendo
/// `confirmacoes_acao_decidir_status()` sob `for update`, exatamente como para
/// quem chegou sozinho. Esta change não encosta naquela função.
///
/// A montagem é a que importa: a vaga que sobra é ocupada por OUTRA pessoa
/// depois do convite e antes da resposta. Se um dia alguém "melhorar" o convite
/// para segurar vaga, é aqui que aparece — a convidada entraria como
/// `confirmado` e a outra pessoa é que cairia na fila.

const _uidCriadora = 'c4000000-0000-0000-0000-000000000001';
const _uidRapida = 'c4000000-0000-0000-0000-000000000002';
const _uidConvidada = 'c4000000-0000-0000-0000-000000000003';
const _allUids = [_uidCriadora, _uidRapida, _uidConvidada];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  Future<int> confirmados() async {
    final r = await conn.execute(
      Sql.named(
          "select count(*) from public.confirmacoes_acao where acao_id = @a and status = 'confirmado'"),
      parameters: {'a': actionId},
    );
    return r.first[0]! as int;
  }

  Future<String> statusDe(String uid) async {
    final r = await conn.execute(
      Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
      parameters: {'a': actionId, 'u': uid},
    );
    return r.single.toColumnMap()['status'] as String;
  }

  Future<void> confirmarComo(String uid) => asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
              'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@a, @u)'),
          parameters: {'a': actionId, 'u': uid},
        );
      });

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    groupId = await createGroup(conn, ownerId: _uidCriadora, name: 'Grupo C4');
    await joinGroup(conn, groupId, _uidRapida);
    await joinGroup(conn, groupId, _uidConvidada);

    // Duas vagas: o gatilho `acoes_criador_vira_confirmado` já ocupa uma com
    // quem criou, então sobra exatamente uma para a corrida do teste.
    actionId = await createActionWithCapacity(conn,
        creatorId: _uidCriadora, capacity: 2, name: 'Ação C4');
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

  test('convidar não muda a contagem de confirmados', () async {
    final antes = await confirmados();
    final r = await asUser(
      conn,
      _uidCriadora,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: groupId, invitees: [_uidConvidada]),
    );
    expect(r[_uidConvidada], 'criado');
    expect(await confirmados(), antes,
        reason: 'o convite não confirma presença sozinho');
  });

  test('a vaga que sobrava é de quem confirmar primeiro', () async {
    await confirmarComo(_uidRapida);
    expect(await statusDe(_uidRapida), 'confirmado');
    expect(await confirmados(), 2, reason: 'criadora + quem chegou primeiro');
  });

  test('a pessoa convidada confirma depois e cai na fila', () async {
    await confirmarComo(_uidConvidada);
    expect(await statusDe(_uidConvidada), 'fila');
    expect(await confirmados(), 2,
        reason: 'nenhuma vaga ficou presa esperando a resposta do convite');
  });
}

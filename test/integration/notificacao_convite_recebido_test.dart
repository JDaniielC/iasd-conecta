import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — convite gera aviso para quem foi convidado.
///
/// A idempotência sai de graça e o teste prova isso: convidar de novo pelo mesmo
/// Grupo não gera linha nova em `convites_acao` (o `on conflict do nothing` da
/// RPC), então o gatilho nem dispara. Se um dia alguém trocar aquele
/// `do nothing` por um `do update`, é aqui que aparece — como aviso duplicado.

const _uidConvidante = 'f4000000-0000-0000-0000-000000000001';
const _uidA = 'f4000000-0000-0000-0000-000000000002';
const _uidB = 'f4000000-0000-0000-0000-000000000003';
const _allUids = [_uidConvidante, _uidA, _uidB];

void main() {
  late Connection conn;
  late String grupo, acao;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    final c = await montarCenarioDeConvite(conn,
        donoId: _uidConvidante, membros: [_uidA, _uidB]);
    grupo = c.grupo;
    acao = c.acao;
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    await conn.execute(
      Sql.named('delete from public.convites_acao where acao_id = @a'),
      parameters: {'a': acao},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': acao},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': grupo},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('convite gera um aviso não lido para quem foi convidado', () async {
    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupo, invitees: [_uidA]),
    );

    expect((await tiposDe(conn, _uidA))['convite_recebido'], 1);
    final r = await conn.execute(
      Sql.named(
          'select lida_em, ator_id::text from public.notificacoes where destinatario_id = @d'),
      parameters: {'d': _uidA},
    );
    expect(r.single.toColumnMap()['lida_em'], isNull, reason: 'nasce não lido');
    expect(r.single.toColumnMap()['ator_id'], _uidConvidante);
  });

  test('quem convidou não recebe aviso do próprio convite', () async {
    expect((await tiposDe(conn, _uidConvidante)).containsKey('convite_recebido'),
        isFalse);
  });

  test('convite repetido pelo mesmo Grupo não gera segundo aviso', () async {
    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupo, invitees: [_uidA]),
    );
    expect((await tiposDe(conn, _uidA))['convite_recebido'], 1,
        reason: 'o convite não duplicou, então o gatilho não disparou');
  });

  test('convite em lote gera um aviso por pessoa', () async {
    final r = await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupo, invitees: [_uidA, _uidB]),
    );
    expect(r[_uidB], 'criado');
    expect((await tiposDe(conn, _uidB))['convite_recebido'], 1);
    expect((await tiposDe(conn, _uidA))['convite_recebido'], 1,
        reason: 'quem já tinha convite continua com um aviso só');
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — o aviso de aceite NÃO guarda o status.
///
/// Quem cai na fila é promovido depois por `promover_fila_acao`. Um aviso com o
/// status congelado passaria a mentir a partir daí — o mesmo defeito que a
/// decisão "desconfirmação é registrada" evita em `log-de-mudancas`.
/// A tela lê `confirmacoes_acao` na hora de renderizar e diz o estado de agora.

const _uidConvidante = 'f6000000-0000-0000-0000-000000000001';
const _uidNaFila = 'f6000000-0000-0000-0000-000000000002';
const _allUids = [_uidConvidante, _uidNaFila];

void main() {
  late Connection conn;
  late String grupo, acao;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    // Uma vaga: `acoes_criador_vira_confirmado` já a ocupa com quem criou.
    final c = await montarCenarioDeConvite(conn,
        donoId: _uidConvidante, membros: [_uidNaFila], limiteVagas: 1);
    grupo = c.grupo;
    acao = c.acao;
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where acao_id = @a'),
      parameters: {'a': acao},
    );
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

  test('quem cai na fila também gera convite_aceito, e o aviso não guarda o '
      'status', () async {
    await asUser(
      conn,
      _uidConvidante,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupo, invitees: [_uidNaFila]),
    );
    await asUser(conn, _uidNaFila, () async {
      await conn.execute(
        Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@a, @u)'),
        parameters: {'a': acao, 'u': _uidNaFila},
      );
    });

    final status = await conn.execute(
      Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
      parameters: {'a': acao, 'u': _uidNaFila},
    );
    expect(status.single.toColumnMap()['status'], 'fila');
    expect((await tiposDe(conn, _uidConvidante))['convite_aceito'], 1,
        reason: 'responder ao convite é o fato, não conseguir vaga');

    // A tabela não tem onde guardar status — é a garantia estrutural, e não uma
    // promessa de que ninguém vai gravar.
    final colunas = await conn.execute(
      "select column_name from information_schema.columns "
      "where table_schema = 'public' and table_name = 'notificacoes'",
    );
    expect(
      colunas.map((c) => c.toColumnMap()['column_name']),
      isNot(contains('status')),
    );
  });

  test('promover a fila depois não gera aviso novo nem deixa o antigo mentindo',
      () async {
    final antes = await tiposDe(conn, _uidConvidante);
    await asUser(conn, _uidConvidante, () async {
      await conn.execute(
        Sql.named(
            'delete from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
        parameters: {'a': acao, 'u': _uidConvidante},
      );
    });

    final status = await conn.execute(
      Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
      parameters: {'a': acao, 'u': _uidNaFila},
    );
    expect(status.single.toColumnMap()['status'], 'confirmado',
        reason: 'foi promovida');
    expect(await tiposDe(conn, _uidConvidante), antes,
        reason: 'promoção é update, e o gatilho de aceite é só de insert');
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — a resposta ao convite volta para quem chamou.
///
/// O gatilho de aceite é `after insert` em `confirmacoes_acao`, e grava UM aviso
/// POR CONVITE existente para aquele par (Ação, pessoa). É o que faz duas
/// pessoas que convidaram a mesma pessoa receberem cada uma o seu, e o que faz
/// quem confirmou sem ter sido convidado não gerar nada.
///
/// `after`, nunca `before`: precisa rodar depois do gatilho que decide
/// confirmado/fila. E é `insert`, não `update`, então promover a fila depois não
/// gera aviso duplicado — coberto em `notificacao_fila_test.dart`.

const _uidJovens = 'f5000000-0000-0000-0000-000000000001';
const _uidMusica = 'f5000000-0000-0000-0000-000000000002';
const _uidConvidada = 'f5000000-0000-0000-0000-000000000003';
const _uidSozinha = 'f5000000-0000-0000-0000-000000000004';
const _allUids = [_uidJovens, _uidMusica, _uidConvidada, _uidSozinha];

void main() {
  late Connection conn;
  late String grupo, acao;
  late String grupoSecundario;

  Future<void> confirmar(String uid) => asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
              'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@a, @u)'),
          parameters: {'a': acao, 'u': uid},
        );
      });

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(0, 10)}');
    }
    final c = await montarCenarioDeConvite(conn,
        donoId: _uidJovens, membros: [_uidMusica, _uidConvidada, _uidSozinha]);
    grupo = c.grupo;
    acao = c.acao;
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where acao_id in '
          '(select id from public.acoes where criador_id = any(@us::uuid[]))'),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.convites_acao where acao_id in '
          '(select id from public.acoes where criador_id = any(@us::uuid[]))'),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = any(@us::uuid[])'),
      parameters: {'us': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = any(@gs::uuid[])'),
      parameters: {'gs': [grupo, grupoSecundario]},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('aceitar avisa quem convidou, e cada convidante recebe o seu', () async {
    // Pelo MESMO Grupo, o segundo convite não cria linha — a PK é
    // (acao, convidado, grupo). Para haver dois convidantes de verdade é
    // preciso dois Grupos, e é isso que este caso monta. Sem o segundo Grupo o
    // teste diria "dois" e provaria um.
    final segundo = await montarCenarioDeConvite(conn,
        donoId: _uidMusica, membros: [_uidConvidada]);
    grupoSecundario = segundo.grupo;

    await asUser(
      conn,
      _uidJovens,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupo, invitees: [_uidConvidada]),
    );
    await asUser(
      conn,
      _uidMusica,
      () => convidarParaAcao(conn,
          actionId: acao, groupId: grupoSecundario, invitees: [_uidConvidada]),
    );

    await confirmar(_uidConvidada);

    expect((await tiposDe(conn, _uidJovens))['convite_aceito'], 1);
    expect((await tiposDe(conn, _uidMusica))['convite_aceito'], 1,
        reason: 'um aviso POR CONVITE, e são dois convites de pessoas diferentes');
    expect((await tiposDe(conn, _uidConvidada)).containsKey('convite_aceito'),
        isFalse, reason: 'quem aceitou não avisa a si mesma');
  });

  test('confirmar sem ter sido convidada não gera aviso nenhum', () async {
    final antes = await tiposDe(conn, _uidJovens);
    await confirmar(_uidSozinha);
    expect(await tiposDe(conn, _uidJovens), antes);
  });

  test('desistir depois de aceitar não gera aviso novo', () async {
    final antes = await tiposDe(conn, _uidJovens);
    await asUser(conn, _uidConvidada, () async {
      await conn.execute(
        Sql.named(
            'delete from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
        parameters: {'a': acao, 'u': _uidConvidada},
      );
    });
    expect(await tiposDe(conn, _uidJovens), antes,
        reason: 'o gatilho de aceite é só de insert');
  });

  test('recusar avisa quem convidou', () async {
    await asUser(conn, _uidConvidada, () async {
      await conn.execute(
        Sql.named(
            'update public.convites_acao set recusado_em = now() where acao_id = @a'),
        parameters: {'a': acao},
      );
    });
    expect((await tiposDe(conn, _uidJovens))['convite_recusado'], 1);
  });
}

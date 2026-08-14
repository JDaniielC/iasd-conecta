import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'mudancas_helper.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — participação, confirmação e
/// arquivamento.
///
/// O caso que mais importa é o da fila: o gatilho de registro é `after insert` e
/// lê `new.status` JÁ DECIDIDO por `confirmacoes_acao_decidir_status()`, que é
/// `before insert` e roda sob `for update`. Se alguém um dia reimplementar a
/// regra de capacidade aqui, este teste é o que fica vermelho.

const _uidDona = 'd3000000-0000-0000-0000-000000000001';
const _uidPrimeira = 'd3000000-0000-0000-0000-000000000002';
const _uidSegunda = 'd3000000-0000-0000-0000-000000000003';
const _allUids = [_uidDona, _uidPrimeira, _uidSegunda];

void main() {
  late Connection conn;
  late String groupId;

  Future<void> confirmarComo(String uid, String actionId) =>
      asUser(conn, uid, () async {
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
    groupId = await createGroup(conn, ownerId: _uidDona, name: 'Grupo D3');
  });

  tearDownAll(() async {
    await limparMudancasDoGrupo(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where acao_id in '
          '(select id from public.acoes where criador_id = @u)'),
      parameters: {'u': _uidDona},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @u'),
      parameters: {'u': _uidDona},
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

  test('criar Grupo gera 1 participacao_entrou — o Dono, pelo gatilho que já '
      'existia', () async {
    expect((await tiposDoGrupo(conn, groupId))['participacao_entrou'], 1);
  });

  test('entrar e sair geram um registro cada', () async {
    await asUser(conn, _uidPrimeira, () async {
      await conn.execute(
        Sql.named(
            'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@g, @u)'),
        parameters: {'g': groupId, 'u': _uidPrimeira},
      );
    });
    expect((await tiposDoGrupo(conn, groupId))['participacao_entrou'], 2);

    await asUser(conn, _uidPrimeira, () async {
      await conn.execute(
        Sql.named(
            'delete from public.participacoes_grupo where grupo_id = @g and usuario_id = @u'),
        parameters: {'g': groupId, 'u': _uidPrimeira},
      );
    });
    expect((await tiposDoGrupo(conn, groupId))['participacao_saiu'], 1);
  });

  test('confirmação dentro do limite é confirmado; além do limite é fila',
      () async {
    // Uma vaga: `acoes_criador_vira_confirmado` já a ocupa com quem criou.
    final r = await conn.execute(
      Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas) "
          "values ('D3 lotada', now() + interval '5 days', 'Sede', @c, 1) returning id"),
      parameters: {'c': _uidDona},
    );
    final actionId = r.single.toColumnMap()['id']! as String;

    var tipos = await tiposDaAcao(conn, actionId);
    expect(tipos['confirmacao_confirmado'], 1, reason: 'quem criou');

    await confirmarComo(_uidSegunda, actionId);
    tipos = await tiposDaAcao(conn, actionId);
    expect(tipos['confirmacao_fila'], 1);
    expect(tipos['confirmacao_confirmado'], 1,
        reason: 'o gatilho LÊ o status decidido, não decide de novo');
  });

  test('desconfirmar e sair da fila geram o mesmo tipo', () async {
    final r = await conn.execute(
      Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas) "
          "values ('D3 saidas', now() + interval '5 days', 'Sede', @c, 1) returning id"),
      parameters: {'c': _uidDona},
    );
    final actionId = r.single.toColumnMap()['id']! as String;
    await confirmarComo(_uidSegunda, actionId); // cai na fila

    await asUser(conn, _uidSegunda, () async {
      await conn.execute(
        Sql.named(
            'delete from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
        parameters: {'a': actionId, 'u': _uidSegunda},
      );
    });
    await asUser(conn, _uidDona, () async {
      await conn.execute(
        Sql.named(
            'delete from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
        parameters: {'a': actionId, 'u': _uidDona},
      );
    });

    final tipos = await tiposDaAcao(conn, actionId);
    expect(tipos['confirmacao_cancelada'], 2,
        reason: 'sair da fila e desconfirmar são o mesmo fato para quem lê');
  });

  test('promoção da fila vira confirmação no registro', () async {
    // C2 da convergência. Sem isto, a última palavra do registro sobre quem foi
    // promovido continuava sendo `confirmacao_fila`, e a seção diria "entrou na
    // fila" para alguém que já tem vaga.
    final r = await conn.execute(
      Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas) "
          "values ('D3 promocao', now() + interval '5 days', 'Sede', @c, 1) returning id"),
      parameters: {'c': _uidDona},
    );
    final actionId = r.single.toColumnMap()['id']! as String;
    await confirmarComo(_uidSegunda, actionId); // fila

    expect((await tiposDaAcao(conn, actionId))['confirmacao_confirmado'], 1,
        reason: 'só quem criou, por enquanto');

    // Quem tinha a vaga desiste; o gatilho que já existia promove a próxima.
    await asUser(conn, _uidDona, () async {
      await conn.execute(
        Sql.named(
            'delete from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
        parameters: {'a': actionId, 'u': _uidDona},
      );
    });

    final status = await conn.execute(
      Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @a and usuario_id = @u'),
      parameters: {'a': actionId, 'u': _uidSegunda},
    );
    expect(status.single.toColumnMap()['status'], 'confirmado');

    expect((await tiposDaAcao(conn, actionId))['confirmacao_confirmado'], 2,
        reason: 'o registro acompanhou a promoção');
  });

  test('confirmação recusada não gera registro', () async {
    // Não dá para nascer cancelada: `acoes_criador_vira_confirmado` confirma
    // quem criou, e `confirmacoes_acao_decidir_status` recusa presença em Ação
    // cancelada. Nasce viva e é cancelada em seguida.
    final r = await conn.execute(
      Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id) "
          "values ('D3 cancelada', now() + interval '5 days', 'Sede', @c) returning id"),
      parameters: {'c': _uidDona},
    );
    final actionId = r.single.toColumnMap()['id']! as String;
    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @a'),
      parameters: {'a': actionId},
    );
    final antes = await tiposDaAcao(conn, actionId);

    // try/catch e não `expectLater`: a exceção vem do servidor por dentro do
    // `asUser`, e o `reset role` do `finally` roda depois — com `expectLater` o
    // erro escapa como falha do teste em vez de ser capturado.
    Object? erro;
    try {
      await confirmarComo(_uidSegunda, actionId);
    } catch (e) {
      erro = e;
    }
    expect(erro, isA<ServerException>());

    expect(await tiposDaAcao(conn, actionId), antes,
        reason: 'operação recusada não deixa rastro');
  });

  test('arquivar Grupo gera 1 grupo_arquivado', () async {
    await conn.execute(
      Sql.named('update public.grupos set arquivado_em = now() where id = @g'),
      parameters: {'g': groupId},
    );
    expect((await tiposDoGrupo(conn, groupId))['grupo_arquivado'], 1);
  });
}

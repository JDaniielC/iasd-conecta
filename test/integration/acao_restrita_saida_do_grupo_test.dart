import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — participação é a chave, e perder a chave
/// tranca a porta na leitura seguinte.
///
/// A policy consulta `participacoes_grupo` a cada leitura, então não há cache
/// nem sessão a invalidar: a linha some assim que a participação some. Este
/// arquivo prova isso pelos três caminhos que tiram alguém de um Grupo —
/// sair, ser removido pelo Dono, e o Grupo ser arquivado.
///
/// Arquivar é o caso que engana. `arquivar_grupo` NÃO apaga participação
/// (20260809230000_arquivar_grupo.sql:303) — ela cancela as Ações futuras
/// confirmadas e descarta as candidatas. Então a Ação restrita continua
/// restrita e continua visível para quem participava: arquivar tira o Grupo de
/// circulação, não redistribui quem enxerga o quê.

const _uidOwner = 'a6000000-0000-0000-0000-000000000001';
const _uidLeaver = 'a6000000-0000-0000-0000-000000000002';
const _uidRemoved = 'a6000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidLeaver, _uidRemoved];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;
  late String restrictedId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A6');
    await createTestProfile(conn, _uidLeaver, name: 'Quem Sai A6');
    await createTestProfile(conn, _uidRemoved, name: 'Quem E Removido A6');

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo A6');
    await joinGroup(conn, groupId, _uidLeaver);
    await joinGroup(conn, groupId, _uidRemoved);
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidOwner);

    restrictedId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'Restrita A6',
    );
    // Vencedora: `confirmada = true` é o que faz `arquivar_grupo` cancelá-la em
    // vez de descartá-la, que é o caso que este arquivo quer observar.
    await makeWinner(conn, roundId, restrictedId);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
          'update public.rodadas_votacao set vencedora_id = null where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    // Sem apagar `participacoes_grupo` à mão: o gatilho
    // `participacoes_grupo_dono_nao_sai_sem_transferir` recusa a saída do Dono
    // ("transfira a posse do grupo antes de sair"). A FK do Grupo é
    // `on delete cascade`, então apagar o Grupo leva as participações junto.
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('sair do Grupo esconde a Ação restrita na leitura seguinte', () async {
    expect(
      await asUser(conn, _uidLeaver, () => visibleActionCount(conn, restrictedId)),
      1,
      reason: 'enquanto participa, enxerga',
    );

    await asUser(conn, _uidLeaver, () async {
      await conn.execute(
        Sql.named(
            'delete from public.participacoes_grupo where grupo_id = @g and usuario_id = @u'),
        parameters: {'g': groupId, 'u': _uidLeaver},
      );
    });

    expect(
      await asUser(conn, _uidLeaver, () => visibleActionCount(conn, restrictedId)),
      0,
    );
  });

  test('ser removido pelo Dono esconde a Ação restrita', () async {
    expect(
      await asUser(conn, _uidRemoved, () => visibleActionCount(conn, restrictedId)),
      1,
    );

    await asUser(conn, _uidOwner, () async {
      await conn.execute(
        Sql.named(
            'delete from public.participacoes_grupo where grupo_id = @g and usuario_id = @u'),
        parameters: {'g': groupId, 'u': _uidRemoved},
      );
    });

    expect(
      await asUser(conn, _uidRemoved, () => visibleActionCount(conn, restrictedId)),
      0,
    );
  });

  test('Grupo arquivado mantém a restrição como estava', () async {
    await asUser(conn, _uidOwner, () async {
      await conn.execute(
        Sql.named('select public.arquivar_grupo(@g)'),
        parameters: {'g': groupId},
      );
    });

    final r = await conn.execute(
      Sql.named(
          'select restrita_ao_grupo, cancelada_em from public.acoes where id = @a'),
      parameters: {'a': restrictedId},
    );
    final row = r.single.toColumnMap();
    expect(row['restrita_ao_grupo'], isTrue,
        reason: 'arquivar cancela, não reabre');
    expect(row['cancelada_em'], isNotNull);

    // Quem participava continua enxergando; quem nunca participou, não.
    expect(
      await asUser(conn, _uidOwner, () => visibleActionCount(conn, restrictedId)),
      1,
    );
    expect(await asVisitor(conn, () => visibleActionCount(conn, restrictedId)), 0);
  });
}

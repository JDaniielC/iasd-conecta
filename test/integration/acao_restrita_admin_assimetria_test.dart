import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — DÍVIDA DE SEGURANÇA ACEITA, provada aqui.
///
/// O Administrador do distrito escreve `restrita_ao_grupo` e NÃO lê a Ação
/// restrita. Ele está em `acoes_update_criador_dono_grupo_ou_admin`
/// (`20260724092132_district_admin.sql`) e não está em `acoes_select_visivel` —
/// de propósito: não existe `bypass` de RLS de leitura em lugar nenhum deste
/// app, e criar o primeiro aqui abriria acesso amplo sem que ninguém tenha
/// pedido moderação de Ação de Grupo.
///
/// A consequência foi MEDIDA antes de ser aceita, e o resultado tem dois lados.
///
/// FECHAR o Postgres barra sozinho: a policy de `select` vale também como
/// `with check` implícito do `update`, então ninguém empurra uma linha para
/// fora da própria visibilidade. O Administrador NÃO restringe Ação de Grupo
/// do qual não participa — a escrita é recusada.
///
/// ABRIR é o que fica: desmarcar deixa a linha mais visível, e aí o
/// `with check` implícito não tem o que barrar.
///
///   update ... set restrita_ao_grupo = false where id = `invisível` -> 0 linhas
///   update ... set restrita_ao_grupo = false   -- sem filtro        -> alcança
///
/// E a policy de update do Administrador não recorta por linha — vale para toda
/// Ação. Logo uma escrita sem filtro reabre ao público TODA Ação restrita do
/// distrito, inclusive as que ele nunca pôde ler.
///
/// O terceiro teste afirma esse comportamento REAL, não o desejado. Ele não é
/// um teste de que a coisa está certa; é o marcador da dívida, para ela ser
/// conhecida e não descoberta em produção. Se um dia o recuo previsto no design
/// for aplicado (pôr a coluna em `acoes_protege_campos_internos` com condição
/// de criador), é este teste que fica vermelho — e aí a dívida foi paga, não
/// quebrada. Ver SECURITY-AUDIT.md.

const _uidOwner = 'a5000000-0000-0000-0000-000000000001';
const _uidAdmin = 'a5000000-0000-0000-0000-000000000002';
const _allUids = [_uidOwner, _uidAdmin];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;

  Future<bool?> restrictionOf(String actionId) async {
    final r = await conn.execute(
      Sql.named('select restrita_ao_grupo from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    return r.single.toColumnMap()['restrita_ao_grupo'] as bool?;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A5');
    await createTestProfile(conn, _uidAdmin, name: 'Admin A5');
    await createTestDistrictAdmin(conn, _uidAdmin);

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo A5');
    roundId = await createVotingRound(conn, groupId: groupId, openedBy: _uidOwner);
    // O Administrador NÃO entra no Grupo. É o ponto do arquivo.
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
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named(
          'delete from public.administradores_distrito where usuario_id = @u'),
      parameters: {'u': _uidAdmin},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('o Administrador não restringe Ação de Grupo do qual não participa',
      () async {
    final id = await createGroupAction(
        conn, creatorId: _uidOwner, roundId: roundId, name: 'A5 fechada pelo admin');

    // Ele ENXERGA a Ação enquanto ela é pública e está na policy de update.
    // Ainda assim o banco recusa: a linha resultante seria invisível para quem
    // a escreveu, e a policy de `select` vale como `with check` implícito.
    expect(await asUser(conn, _uidAdmin, () => visibleActionCount(conn, id)), 1);

    await expectLater(
      asUser(
        conn,
        _uidAdmin,
        () => conn.execute(
          Sql.named(
              'update public.acoes set restrita_ao_grupo = true where id = @a'),
          parameters: {'a': id},
        ),
      ),
      throwsA(isA<ServerException>()),
    );
    expect(await restrictionOf(id), isFalse);
  });

  test('quem participa do Grupo fecha sem problema — o barrado é sair da '
      'própria visibilidade, não restringir', () async {
    final id = await createGroupAction(
        conn, creatorId: _uidOwner, roundId: roundId, name: 'A5 fechada pela dona');

    final afetadas = await asUser(conn, _uidOwner, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.acoes set restrita_ao_grupo = true where id = @a'),
        parameters: {'a': id},
      );
      return r.affectedRows;
    });
    expect(afetadas, 1);
    expect(await restrictionOf(id), isTrue);
  });

  test('pelo id, o Administrador não reabre o que não enxerga', () async {
    final id = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'A5 restrita de nascença',
    );

    final afetadas = await asUser(conn, _uidAdmin, () async {
      final r = await conn.execute(
        Sql.named(
            'update public.acoes set restrita_ao_grupo = false where id = @a'),
        parameters: {'a': id},
      );
      return r.affectedRows;
    });
    expect(afetadas, 0, reason: 'o filtro traz a regra de leitura junto');
    expect(await restrictionOf(id), isTrue);
  });

  test('DÍVIDA ACEITA: escrita sem filtro alcança a Ação restrita', () async {
    final id = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'A5 alvo da escrita sem filtro',
    );

    // A transação NÃO é decoração: sem filtro, este `update` toca toda linha de
    // `acoes` que o Administrador pode escrever, que é todas. O `rollback`
    // devolve o banco ao que era, para os outros arquivos de teste — que
    // `dart test` roda em paralelo — não herdarem o estrago.
    await asUser(conn, _uidAdmin, () async {
      await conn.execute('begin');
      try {
        await conn.execute(
            'update public.acoes set restrita_ao_grupo = false');
        final r = await conn.execute(
          Sql.named('select restrita_ao_grupo from public.acoes where id = @a'),
          parameters: {'a': id},
        );
        // Dentro da transação ele ainda não a enxerga pela leitura, então a
        // conferência é feita pelo próprio efeito da escrita.
        expect(
          r.isEmpty ? null : r.single.toColumnMap()['restrita_ao_grupo'],
          isNot(isTrue),
          reason: 'a escrita sem filtro alcançou a linha invisível',
        );
      } finally {
        await conn.execute('rollback');
      }
    });

    // Fora da transação, nada mudou.
    expect(await restrictionOf(id), isTrue);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// FR-024 e FR-025 — o que a exclusão de conta faz com as capas de quem sai.
///
/// A assimetria é o ponto, e ela parece inconsistência até se ler o motivo:
///
/// - capa de **Ação avulsa** de quem sai é apagada. A Ação era dela;
/// - capa de **Grupo herdado permanece**. O Grupo continua existindo, com
///   outro Dono, e a capa ilustra o Grupo — não a pessoa. Apagá-la seria
///   estragar o Grupo de terceiros porque alguém saiu.
const _uidLeaving = '7d000000-0000-0000-0000-000000000001';
const _uidHeir = '7d000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;
  late Object groupId;
  late Object standaloneActionId;

  Future<int> countCoversFor(String column, Object id) async {
    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.fotos_capa where $column = @id'),
      parameters: {'id': id},
    );
    return rows.single.toColumnMap()['total'] as int;
  }

  Future<bool> isQueued(String path) async {
    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.capas_a_remover where caminho = @c',
      ),
      parameters: {'c': path},
    );
    return (rows.single.toColumnMap()['total'] as int) == 1;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidLeaving, name: 'Quem Sai CapaExclusao');
    await createTestProfile(conn, _uidHeir, name: 'Herdeira CapaExclusao');
    // O herdeiro precisa ser Administrador do distrito: é para ele que a
    // posse do Grupo vai.
    await createTestDistrictAdmin(conn, _uidHeir);

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo CapaExclusao', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidLeaving},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    final actionRows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, confirmada) "
        "values ('Ação Avulsa CapaExclusao', now() + interval '5 days', 'Praça', @criador, true) returning id",
      ),
      parameters: {'criador': _uidLeaving},
    );
    standaloneActionId = actionRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
        "values (@grupo, @caminho, @uid)",
      ),
      parameters: {
        'grupo': groupId,
        'caminho': 'grupo/$groupId/capa-exclusao.jpg',
        'uid': _uidLeaving,
      },
    );
    await conn.execute(
      Sql.named(
        'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
        "values (@acao, @caminho, @uid)",
      ),
      parameters: {
        'acao': standaloneActionId,
        'caminho': 'acao/$standaloneActionId/capa-exclusao.jpg',
        'uid': _uidLeaving,
      },
    );
  });

  tearDownAll(() async {
    // A fila sai NO FIM, e não aqui. Os deletes de Ação e de Grupo abaixo
    // cascateiam em `fotos_capa`, e o gatilho de enfileiramento põe o caminho
    // de volta — limpar antes deles apagava o que existia e deixava o que a
    // própria limpeza provocava. Medido em 2026-08-10: a capa do Grupo
    // herdado, que este teste exige que PERMANEÇA durante a exclusão (FR-025),
    // reaparecia na fila a cada execução da suíte, ao ser derrubada no
    // teardown.
    await conn.execute(
      Sql.named('delete from public.acoes where id = @id'),
      parameters: {'id': standaloneActionId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    // O herdeiro é Administrador do distrito, e a FK não cascateia — a linha
    // de administradores_distrito precisa sair antes do Perfil.
    await conn.execute(
      Sql.named('delete from public.administradores_distrito where usuario_id = @id'),
      parameters: {'id': _uidHeir},
    );
    await conn.execute(
      Sql.named('delete from public.capas_a_remover where caminho like @p'),
      parameters: {'p': '%capa-exclusao.jpg'},
    );
    await cleanUpTestUser(conn, _uidLeaving);
    await cleanUpTestUser(conn, _uidHeir);
    await conn.close();
  });

  test(
    'FR-024/FR-025: some a capa da Ação avulsa, permanece a do Grupo herdado, '
    'e a exclusão continua funcionando por inteiro',
    () async {
      expect(await countCoversFor('grupo_id', groupId), 1);
      expect(await countCoversFor('acao_id', standaloneActionId), 1);

      await conn.execute('set role authenticated');
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$_uidLeaving\",\"role\":\"authenticated\"}'",
      );
      try {
        await conn.execute('select public.excluir_minha_conta()');
      } finally {
        await conn.execute('reset role');
      }

      // (a) capa de Ação avulsa: some, e o arquivo entra na fila.
      expect(await countCoversFor('acao_id', standaloneActionId), 0);
      expect(
        await isQueued('acao/$standaloneActionId/capa-exclusao.jpg'),
        isTrue,
        reason: 'apagar a linha tem de enfileirar o arquivo, senão fica órfão',
      );

      // (b) capa de Grupo herdado: PERMANECE. O Grupo é de outra pessoa agora.
      expect(await countCoversFor('grupo_id', groupId), 1);
      expect(
        await isQueued('grupo/$groupId/capa-exclusao.jpg'),
        isFalse,
        reason: 'a capa do Grupo herdado não pode entrar na fila de remoção',
      );

      // (c) a exclusão continua funcionando por inteiro: anonimização e
      // herança intactas. A feature 013 não pode ter mexido em nada disso.
      final profileRows = await conn.execute(
        Sql.named(
          'select nome, apelido, telefone, genero, idade, anonimizado_em '
          'from public.perfis where id = @id',
        ),
        parameters: {'id': _uidLeaving},
      );
      final profile = profileRows.single.toColumnMap();
      expect(profile['nome'], 'Membro removido');
      expect(profile['apelido'], isNull);
      expect(profile['telefone'], isNull);
      expect(profile['genero'], isNull);
      expect(profile['idade'], isNull);
      expect(profile['anonimizado_em'], isNotNull);

      // A posse passa ao Administrador do distrito **mais antigo**, e não a
      // um em particular. Fixar `_uidHeir` aqui faria este teste depender de
      // nenhum outro arquivo ter criado um Administrador antes — e
      // `dart test` roda os arquivos em paralelo. Foi assim que ele falhou na
      // primeira execução da suíte inteira, passando sozinho.
      final groupRows = await conn.execute(
        Sql.named(
          'select g.dono_id, '
          '  exists(select 1 from public.administradores_distrito d '
          '         where d.usuario_id = g.dono_id) as dono_e_admin '
          'from public.grupos g where g.id = @id',
        ),
        parameters: {'id': groupId},
      );
      final group = groupRows.single.toColumnMap();
      expect(group['dono_id'], isNot(_uidLeaving),
          reason: 'a posse não pode ficar com quem saiu');
      expect(group['dono_e_admin'], isTrue,
          reason: 'a posse passa a um Administrador do distrito');

      // A Ação avulsa continua existindo, sem capa, com criador anonimizado —
      // parece bug e é a regra da feature 009.
      final actionRows = await conn.execute(
        Sql.named('select count(*) as total from public.acoes where id = @id'),
        parameters: {'id': standaloneActionId},
      );
      expect(actionRows.single.toColumnMap()['total'], 1);
    },
  );
}

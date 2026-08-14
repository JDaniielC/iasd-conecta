import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — o convite não sobrevive à exclusão de Conta
/// como dado pessoal.
///
/// `convites_acao` referencia `perfis(id)` e NUNCA copia o nome. É por isso que
/// as duas FKs de Perfil são sem `on delete cascade`: o Perfil é anonimizado,
/// não apagado (`20260806140000_exclusao_de_conta.sql:142-150` troca o nome por
/// 'Membro removido' e zera apelido, telefone, igreja, gênero e idade).
///
/// Um nome desnormalizado na linha do convite sobreviveria a isso, e a exclusão
/// de Conta deixaria de ser exclusão. Este teste é o que impede alguém de
/// "otimizar" a leitura guardando o nome junto.

const _uidConvidante = 'c8000000-0000-0000-0000-000000000001';
const _uidConvidada = 'c8000000-0000-0000-0000-000000000002';
const _allUids = [_uidConvidante, _uidConvidada];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidConvidante, name: 'Convidante Original C8');
    await createTestProfile(conn, _uidConvidada, name: 'Convidada C8');
    // O Grupo é da pessoa CONVIDADA, não de quem convida: `excluir_minha_conta`
    // recusa quem é Dono de Grupo sem Administrador do distrito para herdar
    // (`20260806140000_exclusao_de_conta.sql`). Quem convida só precisa
    // participar, e é a Conta dele que este teste exclui.
    groupId = await createGroup(conn, ownerId: _uidConvidada, name: 'Grupo C8');
    await joinGroup(conn, groupId, _uidConvidante);
    actionId =
        await createLooseAction(conn, creatorId: _uidConvidante, name: 'Ação C8');

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

  test('a linha do convite nunca guardou o nome', () async {
    final r = await conn.execute(
      "select column_name from information_schema.columns "
      "where table_schema = 'public' and table_name = 'convites_acao'",
    );
    final colunas = r.map((x) => x.toColumnMap()['column_name'] as String).toSet();
    expect(colunas, {
      'acao_id',
      'convidado_id',
      'grupo_id',
      'convidante_id',
      'created_at',
      'recusado_em',
    });
    expect(colunas.where((c) => c.contains('nome')), isEmpty);
  });

  test('depois de excluir a Conta, o nome anterior não sai mais por lugar nenhum',
      () async {
    await asUser(conn, _uidConvidante, () async {
      await conn.execute('select public.excluir_minha_conta()');
    });

    // O convite continua de pé — a exclusão não apaga o que foi entregue.
    final gravados = await convitesGravados(conn, actionId);
    expect(gravados, hasLength(1));
    expect(gravados.single['convidante_id'], _uidConvidante);

    // Mas o nome que sai é o anonimizado, pela única via de nome que existe.
    final nome = await conn.execute(
      Sql.named('select nome_exibido from public.perfil_publico(@u)'),
      parameters: {'u': _uidConvidante},
    );
    expect(nome.single.toColumnMap()['nome_exibido'], 'Membro removido');
    expect(
      nome.single.toColumnMap()['nome_exibido'],
      isNot('Convidante Original C8'),
    );
  });
}

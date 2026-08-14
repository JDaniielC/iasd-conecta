import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — a função de contatos não vira despejo de nomes.
///
/// É O TESTE QUE A CHANGE NÃO FECHA SEM. `contatos_para_convite` é
/// `security definer` sobre `perfis`, que é fechado por `perfis_select_own`, e
/// entrega VÁRIOS NOMES DE UMA VEZ. Um a um o nome de exibição já é público
/// hoje; em lote e sem checagem por dentro, isto seria a lista de nomes do
/// distrito inteiro para qualquer sessão.
///
/// A defesa é não ter parâmetro de Grupo: o filtro é `auth.uid()` por dentro.
/// Estes dois casos são os que provam que a defesa está lá — sessão anônima e
/// sessão autenticada sem Grupo em comum, ambas esperando VAZIO.

const _uidDono = 'c1000000-0000-0000-0000-000000000001';
const _uidMembro = 'c1000000-0000-0000-0000-000000000002';
const _uidForasteiro = 'c1000000-0000-0000-0000-000000000003';
const _allUids = [_uidDono, _uidMembro, _uidForasteiro];

void main() {
  late Connection conn;
  late String groupId;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDono, name: 'Dona C1');
    await createTestProfile(conn, _uidMembro, name: 'Participante C1');
    await createTestProfile(conn, _uidForasteiro, name: 'De Fora C1');

    groupId = await createGroup(conn, ownerId: _uidDono, name: 'Grupo C1');
    await joinGroup(conn, groupId, _uidMembro);
    actionId = await createLooseAction(conn, creatorId: _uidDono, name: 'Ação C1');
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

  test('sessão anônima nem alcança a listagem', () async {
    // `anon` não tem `grant execute` na função. Recusa por permissão, não lista
    // vazia — e aqui isso NÃO é canal lateral: anon não participa de Grupo
    // nenhum, então não há quantidade escondida que o erro deixasse contar. É
    // diferente do caso de `acoes`/`votos`, onde o grant fica de propósito
    // justamente para a linha escondida virar ausência em vez de erro.
    await expectLater(
      asVisitor(conn, () => contatosParaConvite(conn, actionId)),
      throwsA(isA<ServerException>()),
    );
  });

  test('autenticado sem Grupo em comum recebe lista vazia', () async {
    final linhas = await asUser(
        conn, _uidForasteiro, () => contatosParaConvite(conn, actionId));
    expect(linhas, isEmpty);
  });

  test('quem participa recebe a lista do próprio Grupo', () async {
    final linhas =
        await asUser(conn, _uidDono, () => contatosParaConvite(conn, actionId));
    expect(linhas, isNotEmpty);
    expect(
      linhas.map((l) => l['nome_exibido']),
      contains('Participante C1'),
    );
  });

  test('não existe parâmetro pelo qual pedir a lista de outro Grupo', () async {
    // A defesa é a ausência do parâmetro, então o teste prova a assinatura:
    // um `p_grupo_id` numa função definer entregaria qualquer Grupo do distrito.
    final r = await conn.execute(
      "select pg_get_function_identity_arguments(p.oid) as args "
      "from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
      "where n.nspname = 'public' and p.proname = 'contatos_para_convite'",
    );
    expect(r.single.toColumnMap()['args'], 'p_acao_id uuid');
  });

  test('o nome de quem é de fora não vaza para dentro da lista', () async {
    final linhas =
        await asUser(conn, _uidDono, () => contatosParaConvite(conn, actionId));
    expect(linhas.map((l) => l['nome_exibido']), isNot(contains('De Fora C1')));
  });
}

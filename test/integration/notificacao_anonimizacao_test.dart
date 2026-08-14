import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — o aviso referencia o Perfil, nunca o nome.
///
/// A notificação carrega um fato sobre relação entre pessoas ("fulano convidou
/// você"). Se o nome estivesse copiado na linha, ele sobreviveria à exclusão de
/// Conta — que é exatamente o que `20260806140000_exclusao_de_conta.sql:14-16`
/// existe para impedir.

const _uidAtor = 'f9000000-0000-0000-0000-000000000001';
const _uidDona = 'f9000000-0000-0000-0000-000000000002';
const _allUids = [_uidAtor, _uidDona];

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidAtor, name: 'Ator Original F9');
    await createTestProfile(conn, _uidDona, name: 'Dona F9');
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo, ator_id) "
        "values (@d, 'convite_recebido', @a)",
      ),
      parameters: {'d': _uidDona, 'a': _uidAtor},
    );
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, _allUids);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('a linha do aviso não tem onde guardar nome', () async {
    final r = await conn.execute(
      "select column_name from information_schema.columns "
      "where table_schema = 'public' and table_name = 'notificacoes'",
    );
    final colunas =
        r.map((x) => x.toColumnMap()['column_name'] as String).toSet();
    expect(colunas.where((c) => c.contains('nome')), isEmpty);
    expect(colunas, {
      'id', 'destinatario_id', 'tipo', 'ator_id', 'acao_id', 'grupo_id',
      'lida_em', 'created_at',
    });
  });

  test('depois de excluir a Conta, o nome anterior não sai por lugar nenhum',
      () async {
    await asUser(conn, _uidAtor, () async {
      await conn.execute('select public.excluir_minha_conta()');
    });

    // O aviso continua — ele é da pessoa que recebeu, não de quem saiu.
    expect((await tiposDe(conn, _uidDona))['convite_recebido'], 1);

    final nome = await conn.execute(
      Sql.named('select nome_exibido from public.perfil_publico(@u)'),
      parameters: {'u': _uidAtor},
    );
    expect(nome.single.toColumnMap()['nome_exibido'], 'Membro removido');
    expect(nome.single.toColumnMap()['nome_exibido'],
        isNot('Ator Original F9'));
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 015, SC-004 — o dado do Responsável não vaza.
///
/// As três afirmações abaixo são verdadeiras **por construção** hoje: nenhuma
/// política nova foi criada, nenhum grant foi aberto, `perfil_publico()` tem
/// projeção fixa. E é exatamente por isso que precisam de teste — a próxima
/// feature que mexer em `perfis` pode invalidá-las sem querer, e nada gritaria.

const _childUid = '88000000-0000-0000-0000-000000000001';
const _otherUserUid = '88000000-0000-0000-0000-000000000002';

const _allUids = [_childUid, _otherUserUid];

void main() {
  late Connection conn;

  Future<T> readAsUser<T>(String uid, Future<T> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      return await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestUser(conn, uid);
    }
    await createTestProfile(conn, _otherUserUid, name: 'Outra Pessoa');
    final threshold = await conn.execute('select public.limiar_crianca()');
    await conn.execute(
      Sql.named(
        'insert into public.perfis '
        '(id, nome, apelido, genero, idade, consentimento_lgpd_aceito_em, '
        'responsavel_nome, responsavel_contato, autorizacao_responsavel_em, '
        'autorizacao_responsavel_versao) '
        "values (@u, 'Ana Crianca', 'Aninha', 'feminino', @age, now(), "
        "'Maria Silva', 'maria@exemplo.com', now(), '1.2')",
      ),
      parameters: {
        'u': _childUid,
        'age': (threshold.first[0] as num).toInt() - 1,
      },
    );
  });

  tearDownAll(() async {
    await conn.execute(
      "select set_config('app.bypass_autorizacao_responsavel', 'true', true)",
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.execute(
      "select set_config('app.bypass_autorizacao_responsavel', 'false', true)",
    );
    await conn.close();
  });

  test('outro Usuário cadastrado não lê a linha da criança', () async {
    final count = await readAsUser(_otherUserUid, () async {
      final r = await conn.execute(
        Sql.named('select count(*) from public.perfis where id = @u'),
        parameters: {'u': _childUid},
      );
      return (r.first[0] as num).toInt();
    });

    expect(count, 0, reason: 'perfis_select_own restringe à própria linha');
  });

  test(
    'perfil_publico devolve projeção FIXA — não há caminho dela até o '
    'Responsável',
    () async {
      final columns = await readAsUser(_otherUserUid, () async {
        final r = await conn.execute(
          Sql.named('select * from public.perfil_publico(@u)'),
          parameters: {'u': _childUid},
        );
        return r.schema.columns.map((c) => c.columnName ?? '').toList();
      });

      expect(columns, ['id', 'nome_exibido', 'igreja_id']);
      for (final forbidden in [
        'responsavel_nome',
        'responsavel_contato',
        'idade',
        'telefone',
      ]) {
        expect(columns, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );

  test('anon não tem select em perfis — nem com RLS fora do caminho', () async {
    final r = await conn.execute(
      "select has_table_privilege('anon', 'public.perfis', 'SELECT')",
    );
    expect(r.first[0], isFalse,
        reason: 'a leitura de Perfil alheio passa só por perfil_publico');
  });
}

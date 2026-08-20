import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `cobertura-e-tdd`, convergência C1.1 — a recusa da policy
/// `acoes_sugeridas_delete_admin` é **ausência**, não erro.
///
/// A asserção aqui é `affectedRows`, e não `expect(..., throwsA(...))`, porque
/// no Postgres uma policy que recusa não levanta exceção: ela faz a linha não
/// existir para aquela sessão, e o `delete` volta com sucesso sobre zero
/// linhas. Um teste que esperasse exceção passaria pelo motivo errado ou não
/// passaria nunca — ver `CLAUDE.md`, "Recusa de RLS é ausência, não erro".
///
/// Isto foi medido antes de existir: `SuggestedActionRepository.delete`
/// mandava `.delete().eq('id', id)` sem `.select()`, e a tela dizia que a
/// sugestão tinha saído enquanto ela continuava na lista para todo mundo.
///
/// **Este arquivo não cria Administrador do distrito, de propósito.** O caso
/// positivo — Administrador remove, uma linha afetada — já é provado por
/// `acao_sugerida_admin_crud_test.dart:50`, e `administradores_distrito` é
/// estado global: `excluir_minha_conta` transfere Grupo para o Administrador
/// mais antigo, então um Administrador vivo aqui vira herdeiro dos Grupos de
/// `account_deletion_test` e derruba quatro casos daquele arquivo. Medido em
/// 2026-08-20, ao escrever este teste.
///
/// Tudo escopado por UUID próprio; nada é apagado por padrão que outro arquivo
/// possa casar.

// Prefixo próprio, conferido contra os 70 já em uso na suíte em 2026-08-20.
const _uidPlainUser = 'd7b70000-0000-0000-0000-000000000002';
const _categoryId = 'd7b70000-0000-0000-0000-0000000000c1';

void main() {
  late Connection conn;

  Future<String> seedSuggestion(String name) async {
    final row = await conn.execute(
      Sql.named(
        'insert into public.acoes_sugeridas (categoria_id, nome) '
        'values (@c, @n) returning id',
      ),
      parameters: {'c': _categoryId, 'n': name},
    );
    return row.first[0]! as String;
  }

  /// Exatamente o que `SuggestedActionRepository.delete` manda ao banco.
  Future<int> deleteAs(String uid, String suggestionId) => asUser(conn, uid, () async {
        final r = await conn.execute(
          Sql.named('delete from public.acoes_sugeridas where id = @id'),
          parameters: {'id': suggestionId},
        );
        return r.affectedRows;
      });

  Future<int> countById(String suggestionId) async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.acoes_sugeridas where id = @id'),
      parameters: {'id': suggestionId},
    );
    return (r.first[0]! as int);
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidPlainUser, name: 'Usuária Comum');
    await conn.execute(
      Sql.named(
        'insert into public.categorias_grupo (id, nome) values (@id, @n) '
        'on conflict (id) do nothing',
      ),
      parameters: {'id': _categoryId, 'n': 'Categoria C1.1'},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes_sugeridas where categoria_id = @c'),
      parameters: {'c': _categoryId},
    );
    await conn.execute(
      Sql.named('delete from public.categorias_grupo where id = @c'),
      parameters: {'c': _categoryId},
    );
    await cleanUpTestUser(conn, _uidPlainUser);
    await conn.close();
  });

  test('Usuária sem privilégio: ZERO linhas afetadas, e nenhuma exceção',
      () async {
    final id = await seedSuggestion('Sugestão que fica');

    // O ponto do teste: a chamada TERMINA BEM. Se um dia ela passar a lançar,
    // este teste falha e é sinal de mudança de comportamento do Postgres ou da
    // policy — não de defeito no app.
    final affected = await deleteAs(_uidPlainUser, id);

    expect(affected, 0, reason: 'a policy recusa fazendo a linha não existir');
    expect(await countById(id), 1, reason: 'a sugestão continua lá para todos');
  });
}

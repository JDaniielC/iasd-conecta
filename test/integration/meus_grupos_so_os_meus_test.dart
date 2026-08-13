import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _eu = '96000000-0000-0000-0000-000000000001';
const _outra = '96000000-0000-0000-0000-000000000002';
const _meuGrupo = '96000000-0000-0000-0000-00000000000a';
const _grupoDela = '96000000-0000-0000-0000-00000000000b';

/// A regra "Ação de Grupo entra no destaque só para quem participa" se apoia
/// inteira numa linha: o `.eq('usuario_id', uid)` de
/// `GroupRepository.fetchMyGroupIds`.
///
/// **A RLS de `participacoes_grupo` não ajuda aqui, e é de propósito** — é ela
/// que permite `fetchMemberIds` listar os membros de um Grupo alheio, então
/// `authenticated` enxerga as linhas de todo mundo. O primeiro teste abaixo
/// mede isso: sem filtro, a consulta devolve participação de outra pessoa.
///
/// Sem este arquivo nada exercitava a consulta de verdade: todo teste de
/// widget sobrepõe `myGroupIdsProvider`. Tirar aquele `.eq` numa refatoração
/// faria a tarja "Novo no seu Grupo" aparecer para Ação de Grupo de que a
/// pessoa não participa, com a suíte inteira verde.
///
/// Corre como `authenticated`, e não como superusuário, que bypassa RLS e não
/// veria nada disso.
void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _eu, name: 'Pessoa de Teste Um');
    await createTestProfile(conn, _outra, name: 'Pessoa de Teste Dois');
    for (final (id, dono) in [(_meuGrupo, _eu), (_grupoDela, _outra)]) {
      await conn.execute(
        Sql.named(
          "insert into public.grupos (id, nome, categoria, dono_id) "
          "values (@id, @nome, 'Música', @dono)",
        ),
        parameters: {'id': id, 'nome': 'Grupo $id', 'dono': dono},
      );
    }
  });

  tearDownAll(() async {
    await conn.execute('reset role');
    await conn.execute(
      Sql.named('delete from public.grupos where id in (@a, @b)'),
      parameters: {'a': _meuGrupo, 'b': _grupoDela},
    );
    await cleanUpTestUser(conn, _eu);
    await cleanUpTestUser(conn, _outra);
    await conn.close();
  });

  Future<void> comoAuthenticated(String uid) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
  }

  test('a RLS sozinha NÃO limita: sem o filtro vêm as linhas de outra pessoa',
      () async {
    await comoAuthenticated(_eu);
    try {
      final linhas = await conn.execute(
        'select usuario_id from public.participacoes_grupo',
      );
      final donos = linhas.map((r) => r[0] as String).toSet();

      expect(donos, contains(_eu));
      expect(
        donos,
        contains(_outra),
        reason: 'se um dia a RLS passar a restringir, este teste vira o aviso '
            'de que o filtro no cliente deixou de ser a única defesa',
      );
    } finally {
      await conn.execute('reset role');
    }
  });

  test('com o filtro por usuario_id, vem só o Grupo de quem perguntou',
      () async {
    await comoAuthenticated(_eu);
    try {
      // A consulta exata de `GroupRepository.fetchMyGroupIds`.
      final linhas = await conn.execute(
        Sql.named(
          'select grupo_id from public.participacoes_grupo '
          'where usuario_id = @uid',
        ),
        parameters: {'uid': _eu},
      );
      final grupos = linhas.map((r) => r[0] as String).toSet();

      expect(grupos, {_meuGrupo});
      expect(grupos, isNot(contains(_grupoDela)));
    } finally {
      await conn.execute('reset role');
    }
  });

  test('a outra pessoa vê o Grupo dela, não o meu', () async {
    await comoAuthenticated(_outra);
    try {
      final linhas = await conn.execute(
        Sql.named(
          'select grupo_id from public.participacoes_grupo '
          'where usuario_id = @uid',
        ),
        parameters: {'uid': _outra},
      );

      expect(linhas.map((r) => r[0] as String).toSet(), {_grupoDela});
    } finally {
      await conn.execute('reset role');
    }
  });
}

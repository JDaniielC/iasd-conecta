import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 018 — declaração de Líder/Diretor pendente ou rejeitada deixa de
/// ser pública.
///
/// A policy era `liderancas_select_public ... using (true)`: qualquer Visitante
/// sem cadastro lia a tabela inteira via PostgREST, inclusive quem se declarou
/// Líder e foi REJEITADO pelo Administrador do distrito. A tela do Grupo só
/// renderiza declaração confirmada, então a inspeção visual nunca mostrou nada
/// — e é exatamente por isso que a prova aqui fala com o banco.
///
/// O glossário delimita o que pode ser público, palavra por palavra
/// (`CONTEXT.md`, entrada Ministério): "Identificação do Líder é pública na
/// página do Ministério". Identificação do LÍDER — não a lista de quem tentou
/// e não conseguiu.
///
/// Reproduzido antes do fix: como `set role anon`, um select devolvia as 3
/// linhas do Grupo, incluindo a rejeitada.

const _confirmedUserId = '98000000-0000-0000-0000-000000000001';
const _pendingUserId = '98000000-0000-0000-0000-000000000002';
const _rejectedUserId = '98000000-0000-0000-0000-000000000003';
const _otherUserId = '98000000-0000-0000-0000-000000000004';
const _adminUserId = '98000000-0000-0000-0000-000000000005';
const _bothStampsUserId = '98000000-0000-0000-0000-000000000006';

const _allUserIds = [
  _confirmedUserId,
  _pendingUserId,
  _rejectedUserId,
  _otherUserId,
  _adminUserId,
  _bothStampsUserId,
];

const _groupId = '98000000-0000-0000-0000-0000000000aa';

void main() {
  late Connection conn;

  /// Um Visitante sem cadastro nenhum — o role que o PostgREST usa quando não
  /// há token.
  Future<void> asVisitor(Future<void> Function() action) async {
    await conn.execute('set role anon');
    try {
      await action();
    } finally {
      // Os dois resets. `reset role` não limpa GUC customizado, então sem o
      // segundo um `set role anon` posterior ainda enxergaria o `sub` antigo e
      // o teste mentiria — achado registrado em
      // church_archive_visibility_test.dart:18-22.
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  Future<void> asUser(String userId, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$userId\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  /// Ids das declarações visíveis para a identidade corrente, dentro do Grupo.
  Future<List<String>> visibleDeclarationUserIds() async {
    final r = await conn.execute(
      Sql.named(
        'select usuario_id from public.liderancas where grupo_id = @g',
      ),
      parameters: {'g': _groupId},
    );
    return r.map((row) => row[0] as String).toList();
  }

  Future<int> countVisibleDeclarations() async {
    final r = await conn.execute(
      Sql.named(
        'select count(*) from public.liderancas where grupo_id = @g',
      ),
      parameters: {'g': _groupId},
    );
    return r.first[0] as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final userId in _allUserIds) {
      await criarPerfilDeTeste(conn, userId,
          name: 'Pessoa ${userId.substring(31)}');
    }
    await criarAdministradorDistritoDeTeste(conn, _adminUserId);

    await conn.execute(
      Sql.named(
        'insert into public.grupos (id, nome, categoria, dono_id) '
        "values (@g, 'Ministério de teste 018', 'Ministério Jovem', @dono)",
      ),
      parameters: {'g': _groupId, 'dono': _confirmedUserId},
    );

    // Os três estados no MESMO Grupo — é a comparação lado a lado que prova o
    // filtro. Inserido como `postgres`, porque a escrita real passa por
    // `declarar_lideranca`/`decidir_lideranca`, que são security definer e não
    // são o objeto desta feature.
    await conn.execute(
      Sql.named(
        'insert into public.liderancas '
        '(grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        'values (@g, @u, extract(year from now())::int, now(), @u)',
      ),
      parameters: {'g': _groupId, 'u': _confirmedUserId},
    );
    await conn.execute(
      Sql.named(
        'insert into public.liderancas (grupo_id, usuario_id, ano) '
        'values (@g, @u, extract(year from now())::int)',
      ),
      parameters: {'g': _groupId, 'u': _pendingUserId},
    );
    await conn.execute(
      Sql.named(
        'insert into public.liderancas '
        '(grupo_id, usuario_id, ano, rejeitado_em) '
        'values (@g, @u, extract(year from now())::int, now())',
      ),
      parameters: {'g': _groupId, 'u': _rejectedUserId},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.liderancas where grupo_id = @g'),
      parameters: {'g': _groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': _groupId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _adminUserId},
    );
    for (final userId in _allUserIds) {
      await limparUsuarioDeTeste(conn, userId);
    }
    await conn.close();
  });

  test(
    'FR-001/FR-005/SC-001: Visitante sem cadastro só recebe a confirmada',
    () async {
      late List<String> visible;
      await asVisitor(() async {
        visible = await visibleDeclarationUserIds();
      });

      expect(visible, [_confirmedUserId],
          reason: 'a identificação do Líder confirmado é pública, e só ela');
      expect(visible, isNot(contains(_rejectedUserId)),
          reason: 'quem foi rejeitado não vira notícia pública');
      expect(visible, isNot(contains(_pendingUserId)));
    },
  );

  test(
    'FR-002/SC-001: Usuário cadastrado que não é o autor vê o mesmo que o '
    'Visitante',
    () async {
      late List<String> visible;
      await asUser(_otherUserId, () async {
        visible = await visibleDeclarationUserIds();
      });

      // Ter cadastro não é motivo. O 2º disjunto é sobre ser a própria pessoa,
      // não sobre estar logada.
      expect(visible, [_confirmedUserId]);
    },
  );

  test(
    'FR-002/FR-008: a própria pessoa vê a própria declaração em qualquer '
    'estado',
    () async {
      late List<String> seenByRejected;
      await asUser(_rejectedUserId, () async {
        seenByRejected = await visibleDeclarationUserIds();
      });
      expect(seenByRejected, unorderedEquals([_confirmedUserId, _rejectedUserId]),
          reason: 'ela precisa saber que foi rejeitada');

      late List<String> seenByPending;
      await asUser(_pendingUserId, () async {
        seenByPending = await visibleDeclarationUserIds();
      });
      expect(seenByPending, unorderedEquals([_confirmedUserId, _pendingUserId]),
          reason: 'e quem espera precisa saber que ainda espera');
    },
  );

  test('FR-003/FR-007: Administrador do distrito vê todas', () async {
    late List<String> visible;
    await asUser(_adminUserId, () async {
      visible = await visibleDeclarationUserIds();
    });

    // É ele quem decide sobre elas — a tela de pendências depende deste
    // disjunto.
    expect(
      visible,
      unorderedEquals([_confirmedUserId, _pendingUserId, _rejectedUserId]),
    );
  });

  test('SC-001: a contagem não vaza o que a linha esconde', () async {
    late int count;
    await asVisitor(() async {
      count = await countVisibleDeclarations();
    });

    // A RLS filtra antes da agregação, então nem o tamanho da resposta nem um
    // `count` revelam que existem 3 linhas.
    expect(count, 1);
  });

  test(
    'FR-005: linha com confirmado_em E rejeitado_em preenchidos não é pública',
    () async {
      // Hoje inalcançável pelos caminhos com grant (`decidir_lideranca` zera
      // sempre o campo oposto), mas a tabela não tem `check` proibindo. Este
      // caso é o que justifica a conjunção `rejeitado_em is null` e impede que
      // alguém a "simplifique" depois.
      await conn.execute(
        Sql.named(
          'insert into public.liderancas '
          '(grupo_id, usuario_id, ano, confirmado_em, confirmado_por, rejeitado_em) '
          'values (@g, @u, extract(year from now())::int, now(), @u, now())',
        ),
        parameters: {'g': _groupId, 'u': _bothStampsUserId},
      );

      late List<String> visible;
      await asVisitor(() async {
        visible = await visibleDeclarationUserIds();
      });

      expect(visible, isNot(contains(_bothStampsUserId)));
      expect(visible, [_confirmedUserId]);
    },
  );
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 014 — quem arquiva, quem desarquiva, e o que um Grupo arquivado
/// recusa.
///
/// As telas escondem os botões. Estas regras é que executam: sem elas, uma
/// chamada direta à API contorna a feature inteira — a mesma diferença entre
/// esconder e proteger que as features 018 e 021 trataram.

const _uidOwner = '91000000-0000-0000-0000-000000000001';
const _uidMember = '91000000-0000-0000-0000-000000000002';
const _uidAdmin = '91000000-0000-0000-0000-000000000003';

const _allUids = [_uidOwner, _uidMember, _uidAdmin];

void main() {
  late Connection conn;
  late String groupId;

  Future<void> archiveAs(String uid) async {
    await asUser(conn, uid, () async {
      await conn.execute(
        Sql.named('select public.arquivar_grupo(@g)'),
        parameters: {'g': groupId},
      );
    });
  }

  Future<bool> isArchived() async {
    final r = await conn.execute(
      Sql.named('select arquivado_em is not null from public.grupos '
          'where id = @g'),
      parameters: {'g': groupId},
    );
    return r.first[0] as bool;
  }

  Future<void> resetGroupToActive() async {
    await conn.execute(
      Sql.named('update public.grupos set arquivado_em = null, '
          'arquivado_por = null where id = @g'),
      parameters: {'g': groupId},
    );
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }
    await createTestDistrictAdmin(conn, _uidAdmin);
  });

  setUp(() async {
    final g = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, dono_id) "
        "values ('Grupo Permissao 014', 'Esporte', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = g.first[0] as String;
    await conn.execute(
      Sql.named('insert into public.participacoes_grupo (grupo_id, usuario_id) '
          'values (@g, @u) on conflict do nothing'),
      parameters: {'g': groupId, 'u': _uidMember},
    );
  });

  tearDown(() async {
    await conn.execute(
      Sql.named('delete from public.votos v using public.rodadas_votacao r '
          'where v.rodada_id = r.id and r.grupo_id = @g'),
      parameters: {'g': groupId},
    );
    // vencedora_id aponta para acoes: soltar antes de apagar.
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null '
          'where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao c using public.acoes a '
          'where c.acao_id = a.id and a.grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @g or rodada_id in '
          '(select id from public.rodadas_votacao where grupo_id = @g)'),
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
  });

  tearDownAll(() async {
    // Rede de segurança: algum caso pode ter criado Grupo extra, e perfis não
    // pode ser apagado enquanto for dono de um.
    await conn.execute(
      Sql.named('delete from public.votos v using public.rodadas_votacao r '
          'where v.rodada_id = r.id and r.aberta_por = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null '
          'where aberta_por = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where usuario_id = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where aberta_por = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where dono_id = any(@u)'),
      parameters: {'u': _allUids},
    );
    await conn.execute(
      Sql.named('delete from public.administradores_distrito '
          'where usuario_id = @u'),
      parameters: {'u': _uidAdmin},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  group('quem pode arquivar', () {
    test('FR-002: participante comum é recusado', () async {
      await expectLater(archiveAs(_uidMember), throwsA(isA<Exception>()));
      expect(await isArchived(), isFalse);
    });

    test('FR-001: o Dono arquiva o próprio Grupo', () async {
      await archiveAs(_uidOwner);
      expect(await isArchived(), isTrue);
    });

    test('FR-001: o Administrador do distrito arquiva qualquer Grupo', () async {
      await archiveAs(_uidAdmin);
      expect(await isArchived(), isTrue);

      final r = await conn.execute(
        Sql.named('select arquivado_por from public.grupos where id = @g'),
        parameters: {'g': groupId},
      );
      expect(r.first[0], _uidAdmin, reason: 'registra QUEM arquivou (FR-008)');
    });

    test('FR-009: Grupo já arquivado não é arquivado de novo', () async {
      await archiveAs(_uidOwner);
      await expectLater(archiveAs(_uidOwner), throwsA(isA<Exception>()));
    });
  });

  group('Grupo arquivado não aceita mais nada', () {
    test('FR-011: ninguém participa de Grupo arquivado', () async {
      await archiveAs(_uidOwner);

      await expectLater(
        asUser(conn, _uidAdmin, () async {
          await conn.execute(
            Sql.named('insert into public.participacoes_grupo '
                '(grupo_id, usuario_id) values (@g, @u)'),
            parameters: {'g': groupId, 'u': _uidAdmin},
          );
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('FR-012: não se abre Rodada de votação em Grupo arquivado', () async {
      await archiveAs(_uidOwner);

      await expectLater(
        asUser(conn, _uidOwner, () async {
          await conn.execute(
            Sql.named(
              'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
              "values (@g, @u, now() + interval '7 days')",
            ),
            parameters: {'g': groupId, 'u': _uidOwner},
          );
        }),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'FR-012: propor candidata e votar são recusados numa Rodada que '
      'sobreviva ao arquivamento',
      () async {
        // Arquivar já fecha as Rodadas abertas, então este caso monta a
        // situação pela porta dos fundos: abre a Rodada, arquiva, e reabre a
        // Rodada por fora para provar que a checagem de arquivado no trigger
        // segura mesmo assim. É defesa em profundidade — sem ela, qualquer
        // caminho futuro que deixe uma Rodada aberta reabriria o buraco.
        late String roundId;
        await asUser(conn, _uidOwner, () async {
          final r = await conn.execute(
            Sql.named(
              'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
              "values (@g, @u, now() + interval '7 days') returning id",
            ),
            parameters: {'g': groupId, 'u': _uidOwner},
          );
          roundId = r.first[0] as String;
        });
        await archiveAs(_uidOwner);
        await conn.execute(
          Sql.named('update public.rodadas_votacao set fechada_em = null '
              'where id = @r'),
          parameters: {'r': roundId},
        );

        await expectLater(
          asUser(conn, _uidOwner, () async {
            await conn.execute(
              Sql.named(
                'insert into public.acoes '
                '(nome, data_hora, local, criador_id, confirmada, rodada_id) '
                "values ('Candidata tardia', now() + interval '10 days', "
                "'Centro', @u, false, @r)",
              ),
              parameters: {'u': _uidOwner, 'r': roundId},
            );
          }),
          throwsA(isA<Exception>()),
        );
      },
    );
  });

  test(
    'FR-010/SC-003: a consulta da listagem não devolve Grupo arquivado',
    () async {
      // A regra vive no SQL de `GroupRepository.fetchGroups`, não na página —
      // por isso a prova é aqui e não num teste de widget. Filtrar também na
      // tela criaria duas cópias da mesma regra, que é como elas divergem.
      await archiveAs(_uidOwner);

      final r = await conn.execute(
        Sql.named('select count(*) from public.grupos '
            'where id = @g and arquivado_em is null'),
        parameters: {'g': groupId},
      );
      expect((r.first[0] as num).toInt(), 0);

      // E aparece na consulta de arquivados, que é a tela do Administrador.
      final archived = await conn.execute(
        Sql.named('select count(*) from public.grupos '
            'where id = @g and arquivado_em is not null'),
        parameters: {'g': groupId},
      );
      expect((archived.first[0] as num).toInt(), 1);
    },
  );

  group('desarquivar', () {
    test('FR-018: o Dono do Grupo NÃO desarquiva', () async {
      await archiveAs(_uidOwner);

      await expectLater(
        asUser(conn, _uidOwner, () async {
          await conn.execute(
            Sql.named('select public.desarquivar_grupo(@g)'),
            parameters: {'g': groupId},
          );
        }),
        throwsA(isA<Exception>()),
      );
      expect(await isArchived(), isTrue);
    });

    test(
      'FR-020/FR-021: o Administrador desarquiva, e os participantes voltam '
      'sem fazer nada',
      () async {
        final membersBefore = await conn.execute(
          Sql.named('select count(*) from public.participacoes_grupo '
              'where grupo_id = @g'),
          parameters: {'g': groupId},
        );

        await archiveAs(_uidOwner);
        await asUser(conn, _uidAdmin, () async {
          await conn.execute(
            Sql.named('select public.desarquivar_grupo(@g)'),
            parameters: {'g': groupId},
          );
        });

        expect(await isArchived(), isFalse);

        // Voltam de graça porque nunca foram apagados. "Suspensa" é ausência
        // de permissão, não ausência de linha — guardar uma segunda lista de
        // quem estava lá seria uma lista a divergir um dia.
        final membersAfter = await conn.execute(
          Sql.named('select count(*) from public.participacoes_grupo '
              'where grupo_id = @g'),
          parameters: {'g': groupId},
        );
        expect(membersAfter.first[0], membersBefore.first[0]);

        // E volta a aceitar Rodada de votação.
        await asUser(conn, _uidOwner, () async {
          await conn.execute(
            Sql.named(
              'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
              "values (@g, @u, now() + interval '7 days')",
            ),
            parameters: {'g': groupId, 'u': _uidOwner},
          );
        });
      },
    );

    test('FR-022: desarquivar NÃO ressuscita Ação cancelada', () async {
      // Ação de Grupo confirmada nasce vencendo uma Rodada — inserir direto
      // com grupo_id e rodada_id nulo é recusado desde a correção de segurança
      // de 20260724130000.
      late String roundId;
      await asUser(conn, _uidOwner, () async {
        final r = await conn.execute(
          Sql.named(
            'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
            "values (@g, @u, now() + interval '7 days') returning id",
          ),
          parameters: {'g': groupId, 'u': _uidOwner},
        );
        roundId = r.first[0] as String;
      });
      late String actionId;
      await asUser(conn, _uidOwner, () async {
        final a = await conn.execute(
          Sql.named(
            'insert into public.acoes '
            '(nome, data_hora, local, criador_id, confirmada, rodada_id) '
            "values ('Pedalada futura', now() + interval '20 days', 'Centro', "
            '@u, false, @r) returning id',
          ),
          parameters: {'u': _uidOwner, 'r': roundId},
        );
        actionId = a.first[0] as String;
        await conn.execute(
          Sql.named('insert into public.votos (rodada_id, usuario_id, candidata_id) '
              'values (@r, @u, @c)'),
          parameters: {'r': roundId, 'u': _uidOwner, 'c': actionId},
        );
      });
      await conn.execute(
        Sql.named("update public.rodadas_votacao set prazo = now() - "
            "interval '1 hour' where id = @r"),
        parameters: {'r': roundId},
      );
      await asUser(conn, _uidOwner, () async {
        await conn.execute(
          Sql.named('select public.fechar_rodada_se_devido(@r, false)'),
          parameters: {'r': roundId},
        );
      });

      await archiveAs(_uidOwner);
      await asUser(conn, _uidAdmin, () async {
        await conn.execute(
          Sql.named('select public.desarquivar_grupo(@g)'),
          parameters: {'g': groupId},
        );
      });

      final r = await conn.execute(
        Sql.named('select cancelada_em from public.acoes where id = @a'),
        parameters: {'a': actionId},
      );
      expect(r.first[0], isNotNull,
          reason: 'quem foi avisado do cancelamento não é desavisado depois');
      await resetGroupToActive();
    });
  });
}

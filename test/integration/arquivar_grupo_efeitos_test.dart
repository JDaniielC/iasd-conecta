import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 014 — o que arquivar um Grupo faz, e o que ele NÃO faz.
///
/// Esta feature encosta em quatro das cinco regras centrais do Princípio IV:
/// fila de espera, desempate, descarte de candidatas e revogação de Participar.
/// Arquivar é uma operação de vários passos numa transação, e o modo de falha é
/// **estado parcial** — metade cancelada, metade não. Contar antes e depois é o
/// único jeito de ver isso.
///
/// A asserção (d) é a que mais importa a longo prazo: ela é a única que percebe
/// se alguém um dia "simplificar" `arquivar_grupo` reusando
/// `fechar_rodada_se_devido`. Aquela função APURA — escolheria a mais votada,
/// resolveria empate por sorteio e promoveria a vencedora a Ação confirmada.
/// O resultado seria um encontro marcado por um Grupo que acabou de sair do ar.

const _uidOwner = '92000000-0000-0000-0000-000000000001';
const _uidMemberA = '92000000-0000-0000-0000-000000000002';
const _uidMemberB = '92000000-0000-0000-0000-000000000003';

const _allUids = [_uidOwner, _uidMemberA, _uidMemberB];

void main() {
  late Connection conn;
  late String groupId;
  late String pastActionId;
  late String futureActionAId;
  late String futureActionBId;
  late String openRoundId;
  late String closedRoundId;
  late String closedRoundWinnerId;

  Future<void> asUser(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
      await conn.execute('reset request.jwt.claims');
    }
  }

  Future<int> countOf(String sql, Map<String, dynamic> params) async {
    final r = await conn.execute(Sql.named(sql), parameters: params);
    return (r.first[0] as num).toInt();
  }

  Future<String> createAction({
    required String name,
    required int dayOffset,
    required bool confirmed,
    String? roundId,
    int? seats,
    String? actingAs,
  }) async {
    // Ação candidata passa pelo trigger acoes_candidata_checar_regras, que
    // exige participação por auth.uid() — então ela precisa ser criada com a
    // identidade de quem participa, não como postgres.
    if (actingAs != null) {
      late String createdId;
      await asUser(actingAs, () async {
        createdId = await createAction(
          name: name,
          dayOffset: dayOffset,
          confirmed: confirmed,
          roundId: roundId,
          seats: seats,
        );
      });
      return createdId;
    }
    final r = await conn.execute(
      Sql.named(
        'insert into public.acoes '
        '(nome, data_hora, local, criador_id, confirmada, grupo_id, rodada_id, '
        'limite_vagas) '
        'values (@n, now() + make_interval(days => @off), @l, @c, @conf, @g, @r, @seats) returning id',
      ),
      parameters: {
        'n': name,
        'off': dayOffset,
        'l': 'Centro',
        'c': _uidOwner,
        'conf': confirmed,
        'g': groupId,
        'r': roundId,
        'seats': seats,
      },
    );
    return r.first[0] as String;
  }


  /// Cria uma Ação de Grupo **confirmada** pelo caminho real: abre Rodada,
  /// propõe candidata, vota e fecha apurando.
  ///
  /// Não dá para inserir Ação com `grupo_id` e `rodada_id` nulo — a migration
  /// 20260724130000_fix_rls_security_bugs proíbe, porque era assim que se
  /// forjava Ação de Grupo sem participar do Grupo. Montar o arranjo pelo
  /// caminho real é mais trabalhoso e é o único jeito honesto.
  Future<String> createConfirmedGroupAction({
    required String name,
    required int dayOffset,
    int? seats,
  }) async {
    late String roundId;
    await asUser(_uidOwner, () async {
      final r = await conn.execute(
        Sql.named(
          'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
          "values (@g, @u, now() + interval '7 days') returning id",
        ),
        parameters: {'g': groupId, 'u': _uidOwner},
      );
      roundId = r.first[0] as String;
    });
    final candidateId = await createAction(
      name: name,
      dayOffset: dayOffset,
      confirmed: false,
      roundId: roundId,
      seats: seats,
      actingAs: _uidOwner,
    );
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@r, @u, @c)'),
        parameters: {'r': roundId, 'u': _uidOwner, 'c': candidateId},
      );
    });
    await conn.execute(
      Sql.named("update public.rodadas_votacao set prazo = now() - "
          "interval '1 hour' where id = @r"),
      parameters: {'r': roundId},
    );
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@r, false)'),
        parameters: {'r': roundId},
      );
    });
    return candidateId;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }

    final g = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, dono_id) "
        "values ('Grupo Arquivar 014', 'Esporte', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = g.first[0] as String;
    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) '
        'values (@g, @a), (@g, @b) on conflict do nothing',
      ),
      parameters: {'g': groupId, 'a': _uidMemberA, 'b': _uidMemberB},
    );

    // Ação PASSADA, confirmada. Histórico — não pode ser tocada.
    // A Ação passada nasce futura e depois envelhece. Criá-la já no passado é
    // impossível pelo caminho real: o trigger que confirma o criador bate na
    // regra da feature 011 — Ação encerrada não aceita presença. Envelhecer a
    // linha como postgres é o equivalente honesto de "o tempo passou".
    pastActionId = await createConfirmedGroupAction(
      name: 'Pedalada de julho',
      dayOffset: 5,
    );
    await conn.execute(
      Sql.named("update public.acoes set data_hora = now() - interval '30 days' "
          'where id = @a'),
      parameters: {'a': pastActionId},
    );
    // Duas Ações FUTURAS confirmadas. Uma delas com fila de espera: 1 vaga e
    // 2 pessoas, então a segunda entra na fila. É o caso (c).
    futureActionAId = await createConfirmedGroupAction(
      name: 'Pedalada de setembro',
      dayOffset: 20,
      seats: 1,
    );
    futureActionBId = await createConfirmedGroupAction(
      name: 'Pedalada de outubro',
      dayOffset: 40,
    );

    // Presenças. O criador já entra confirmado por trigger na criação.
    // A Ação passada não recebe presença nova: desde a feature 011, Ação
    // encerrada recusa confirmação — e é correto que recuse. Ela já tem a
    // presença do criador, posta pelo trigger na criação.
    for (final entry in [
      (futureActionAId, _uidMemberA),
      (futureActionAId, _uidMemberB),
      (futureActionBId, _uidMemberA),
    ]) {
      // Cada presença com a identidade de quem confirma — confirmacoes_acao
      // tem RLS de insert própria (auth.uid() = usuario_id).
      await asUser(entry.$2, () async {
        await conn.execute(
          Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) '
            'values (@a, @u) on conflict do nothing',
          ),
          parameters: {'a': entry.$1, 'u': entry.$2},
        );
      });
    }

    // Rodada ABERTA, com duas candidatas e votos.
    await asUser(_uidOwner, () async {
      final r = await conn.execute(
        Sql.named(
          'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
          "values (@g, @u, now() + interval '7 days') returning id",
        ),
        parameters: {'g': groupId, 'u': _uidOwner},
      );
      openRoundId = r.first[0] as String;
    });
    final candidateX = await createAction(
      name: 'Candidata X',
      dayOffset: 15,
      confirmed: false,
      roundId: openRoundId,
      actingAs: _uidOwner,
    );
    await createAction(
      name: 'Candidata Y',
      dayOffset: 16,
      confirmed: false,
      roundId: openRoundId,
      actingAs: _uidOwner,
    );
    for (final uid in [_uidOwner, _uidMemberA]) {
      await asUser(uid, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@r, @u, @c)',
          ),
          parameters: {'r': openRoundId, 'u': uid, 'c': candidateX},
        );
      });
    }

    // Rodada JÁ FECHADA, com vencedora apurada. É o caso (f).
    await asUser(_uidOwner, () async {
      final r = await conn.execute(
        Sql.named(
          'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
          "values (@g, @u, now() + interval '7 days') returning id",
        ),
        parameters: {'g': groupId, 'u': _uidOwner},
      );
      closedRoundId = r.first[0] as String;
    });
    closedRoundWinnerId = await createAction(
      name: 'Vencedora antiga',
      dayOffset: 25,
      confirmed: false,
      roundId: closedRoundId,
      actingAs: _uidOwner,
    );
    // Fechada pelo caminho REAL, com apuração de verdade. Promover a vencedora
    // com um `update ... set confirmada = true` seria recusado pelo trigger de
    // segurança que a auditoria de 2026-07 instalou — e usar o caminho real
    // deixa este arranjo mais próximo do que acontece em produção.
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@r, @u, @c)',
        ),
        parameters: {
          'r': closedRoundId,
          'u': _uidOwner,
          'c': closedRoundWinnerId,
        },
      );
    });
    await conn.execute(
      Sql.named("update public.rodadas_votacao set prazo = now() - "
          "interval '1 hour' where id = @r"),
      parameters: {'r': closedRoundId},
    );
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@r, false)'),
        parameters: {'r': closedRoundId},
      );
    });
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.votos v using public.rodadas_votacao r '
          'where v.rodada_id = r.id and r.grupo_id = @g'),
      parameters: {'g': groupId},
    );
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
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    'arquivar cancela o futuro, preserva o passado e não apura nada',
    () async {
      // --- ANTES ---
      // Escopo: presenças em Ação CONFIRMADA. Presença em Ação candidata é
      // outra coisa — o glossário diz que candidata perdedora "é descartada
      // junto com suas presenças confirmadas", regra da feature 004 e anterior
      // a esta. Contar as duas juntas mediria a regra errada.
      final attendancesBefore = await countOf(
        'select count(*) from public.confirmacoes_acao c '
        'join public.acoes a on a.id = c.acao_id '
        'where a.grupo_id = @g and a.confirmada = true',
        {'g': groupId},
      );
      final candidateAttendancesBefore = await countOf(
        'select count(*) from public.confirmacoes_acao c '
        'join public.acoes a on a.id = c.acao_id '
        'where a.rodada_id = @r',
        {'r': openRoundId},
      );
      expect(candidateAttendancesBefore, greaterThanOrEqualTo(1),
          reason: 'o arranjo precisa ter presença em candidata, senão a '
              'asserção sobre descarte não prova nada');
      final membershipsBefore = await countOf(
        'select count(*) from public.participacoes_grupo where grupo_id = @g',
        {'g': groupId},
      );
      final waitlistedBefore = await countOf(
        "select count(*) from public.confirmacoes_acao "
        "where acao_id = @a and status = 'fila'",
        {'a': futureActionAId},
      );
      expect(waitlistedBefore, greaterThanOrEqualTo(1),
          reason: 'o arranjo precisa ter alguém na fila, senão (c) não prova nada');

      // --- ARQUIVAR ---
      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named('select public.arquivar_grupo(@g)'),
          parameters: {'g': groupId},
        );
      });

      // (a) Ações futuras canceladas; a passada intacta.
      final past = await conn.execute(
        Sql.named('select cancelada_em from public.acoes where id = @a'),
        parameters: {'a': pastActionId},
      );
      expect(past.first[0], isNull,
          reason: 'histórico é histórico — Ação que já aconteceu não é cancelada');

      for (final id in [futureActionAId, futureActionBId]) {
        final r = await conn.execute(
          Sql.named('select cancelada_em from public.acoes where id = @a'),
          parameters: {'a': id},
        );
        expect(r.first[0], isNotNull, reason: 'Ação futura $id');
      }

      // (b) Nenhuma presença sumiu. A Ação aparece cancelada COM quem havia
      //     confirmado — quem organizou precisa saber quem esperava por aquilo.
      final attendancesAfter = await countOf(
        'select count(*) from public.confirmacoes_acao c '
        'join public.acoes a on a.id = c.acao_id '
        'where a.grupo_id = @g and a.confirmada = true',
        {'g': groupId},
      );
      expect(attendancesAfter, attendancesBefore,
          reason: 'a Ação aparece cancelada COM quem havia confirmado — quem '
              'organizou precisa saber quem esperava por aquilo');

      // E o outro lado da mesma moeda: as presenças das candidatas somem junto
      // com elas, que é a regra de descarte que já existia.
      final candidateAttendancesAfter = await countOf(
        'select count(*) from public.confirmacoes_acao c '
        'join public.acoes a on a.id = c.acao_id '
        'where a.rodada_id = @r',
        {'r': openRoundId},
      );
      expect(candidateAttendancesAfter, 0);

      // (c) Ninguém foi promovido da fila. Cancelar não abre vaga.
      final waitlistedAfter = await countOf(
        "select count(*) from public.confirmacoes_acao "
        "where acao_id = @a and status = 'fila'",
        {'a': futureActionAId},
      );
      expect(waitlistedAfter, waitlistedBefore,
          reason: 'promover alguém para uma Ação cancelada seria convidar para '
              'um encontro que não vai acontecer');

      // (d) A Rodada aberta fechou SEM vencedora. É esta asserção que percebe
      //     se alguém reusar fechar_rodada_se_devido aqui.
      final openRound = await conn.execute(
        Sql.named(
          'select fechada_em, vencedora_id from public.rodadas_votacao '
          'where id = @r',
        ),
        parameters: {'r': openRoundId},
      );
      expect(openRound.first[0], isNotNull, reason: 'a Rodada encerrou');
      expect(openRound.first[1], isNull,
          reason: 'e encerrou SEM APURAR — apurar aqui criaria um encontro '
              'marcado por um Grupo que acabou de sair do ar');

      // (e) Todas as candidatas descartadas, nenhuma virou Ação confirmada.
      final remainingCandidates = await countOf(
        'select count(*) from public.acoes where rodada_id = @r',
        {'r': openRoundId},
      );
      expect(remainingCandidates, 0);

      // (f) A Rodada que já estava fechada não foi tocada — nem ela nem a
      //     vencedora que ela havia apurado.
      final closedRound = await conn.execute(
        Sql.named(
          'select vencedora_id from public.rodadas_votacao where id = @r',
        ),
        parameters: {'r': closedRoundId},
      );
      expect(closedRound.first[0], closedRoundWinnerId);
      final winner = await conn.execute(
        Sql.named('select confirmada from public.acoes where id = @a'),
        parameters: {'a': closedRoundWinnerId},
      );
      expect(winner.first[0], isTrue,
          reason: 'apuração anterior ao arquivamento continua de pé');

      // (g) As participações continuam gravadas. "Suspensa" é ausência de
      //     permissão, não ausência de linha — é o que faz desarquivar
      //     devolver todo mundo sem guardar uma segunda lista.
      final membershipsAfter = await countOf(
        'select count(*) from public.participacoes_grupo where grupo_id = @g',
        {'g': groupId},
      );
      expect(membershipsAfter, membershipsBefore);
    },
  );
}

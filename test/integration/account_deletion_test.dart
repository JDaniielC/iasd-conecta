import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 009 — exclusão de conta com anonimização do Perfil.
///
/// Roda como role `authenticated`, nunca como superusuário: superusuário tem
/// BYPASSRLS e não veria falha de policy nem de GRANT.
///
/// Cenários numerados conforme `specs/009-exclusao-de-conta/quickstart.md`.
void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() => conn.close());

  Future<void> asUser(String uid) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
  }

  Future<void> deleteAccount(String uid) async {
    await asUser(uid);
    try {
      await conn.execute('select public.excluir_minha_conta()');
    } finally {
      await conn.execute('reset role');
    }
  }

  Future<int> contar(String sql, Map<String, dynamic> params) async {
    final rows = await conn.execute(Sql.named(sql), parameters: params);
    return rows.single.first! as int;
  }

  /// Cria uma Ação avulsa, com data no passado ou no futuro.
  Future<String> createAction(
    String creatorId, {
    required bool futura,
    int? capacity,
    bool missionaryPair = false,
    String? visitedGender,
  }) async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes "
        "(nome, data_hora, local, criador_id, limite_vagas, eh_dupla_missionaria, genero_visitado) "
        "values (@nome, now() + @deslocamento::interval, 'Praça', @criador, "
        "@limite, @dupla, @genero) returning id",
      ),
      parameters: {
        'nome': futura ? 'Ação futura' : 'Ação passada',
        'deslocamento': futura ? '30 days' : '-30 days',
        'criador': creatorId,
        'limite': capacity,
        'dupla': missionaryPair,
        'genero': visitedGender,
      },
    );
    return rows.single.first! as String;
  }

  Future<void> confirmAttendance(String actionId, String userId) async {
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
      ),
      parameters: {'acao': actionId, 'usuario': userId},
    );
  }

  group('cenário 1 e 2 — anonimização e projeção pública', () {
    const uid = '95100000-0000-0000-0000-000000000001';

    setUpAll(() async {
      await createTestProfile(conn, uid, name: 'Fulana Original');
      await deleteAccount(uid);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.perfis where id = @id'),
        parameters: {'id': uid},
      );
    });

    test('a linha de perfis sobrevive, sem nenhum dado pessoal', () async {
      final rows = await conn.execute(
        Sql.named(
          'select nome, apelido, telefone, igreja_id, genero, idade, anonimizado_em '
          'from public.perfis where id = @id',
        ),
        parameters: {'id': uid},
      );

      final linha = rows.single;
      expect(linha[0], 'Membro removido');
      expect(linha.sublist(1, 6), everyElement(isNull),
          reason: 'apelido, telefone, igreja, gênero e idade têm que sumir');
      expect(linha[6], isNotNull, reason: 'anonimizado_em torna o estado auditável');
    });

    test('o login deixa de existir', () async {
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': uid}),
        0,
      );
    });

    test('perfil_publico devolve "Membro removido"', () async {
      // Trava o coalesce(apelido, nome) contra "simplificação" futura: sem ele,
      // o nome real voltaria a aparecer para todo mundo.
      final rows = await conn.execute(
        Sql.named('select nome_exibido, igreja_id from public.perfil_publico(@id)'),
        parameters: {'id': uid},
      );
      expect(rows.single[0], 'Membro removido');
      expect(rows.single[1], isNull);
    });
  });

  group('cenário 3 — presença em Ação passada fica, em Ação futura some', () {
    const uid = '95100000-0000-0000-0000-000000000002';
    const creatorId = '95100000-0000-0000-0000-000000000003';
    late String pastAction;
    late String futureAction;

    setUpAll(() async {
      await createTestProfile(conn, creatorId, name: 'Criadora das Ações');
      await createTestProfile(conn, uid, name: 'Quem Vai Sair');
      pastAction = await createAction(creatorId, futura: false);
      futureAction = await createAction(creatorId, futura: true);
      await confirmAttendance(pastAction, uid);
      await confirmAttendance(futureAction, uid);
      await deleteAccount(uid);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': creatorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [uid, creatorId]},
      );
      await cleanUpTestUser(conn, creatorId);
    });

    test('a presença na Ação que já aconteceu permanece', () async {
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
          {'acao': pastAction, 'uid': uid},
        ),
        1,
      );
    });

    test('a presença na Ação que ainda vai acontecer some', () async {
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
          {'acao': futureAction, 'uid': uid},
        ),
        0,
      );
    });
  });

  group('cenário 4 — fila de espera anda sozinha (Princípio IV)', () {
    const seatOwner = '95100000-0000-0000-0000-000000000004';
    const inWaitlist = '95100000-0000-0000-0000-000000000005';
    const creatorId = '95100000-0000-0000-0000-000000000006';
    late String actionId;

    setUpAll(() async {
      await createTestProfile(conn, creatorId, name: 'Criadora da Lotada');
      await createTestProfile(conn, seatOwner, name: 'Quem Ocupa a Vaga');
      await createTestProfile(conn, inWaitlist, name: 'Quem Espera');
      // limite 2 porque o criador da Ação já nasce confirmado por trigger:
      // com 1 vaga, ela seria dele e ninguém mais ficaria confirmado.
      actionId = await createAction(creatorId, futura: true, capacity: 2);
      await confirmAttendance(actionId, seatOwner);
      await confirmAttendance(actionId, inWaitlist);
      await deleteAccount(seatOwner);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': creatorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [seatOwner, inWaitlist, creatorId]},
      );
      await cleanUpTestUser(conn, inWaitlist);
      await cleanUpTestUser(conn, creatorId);
    });

    test('quem estava na fila foi promovido a confirmado', () async {
      // Nenhuma linha desta feature promove ninguém — quem faz é o trigger
      // confirmacoes_acao_promover_fila, AFTER DELETE, que já existia.
      final rows = await conn.execute(
        Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
        ),
        parameters: {'acao': actionId, 'uid': inWaitlist},
      );
      expect(rows.single.first, 'confirmado');
    });
  });

  group('Dupla Missionária não fica com vaga de quem saiu (Princípio IV)', () {
    const leavingUser = '95100000-0000-0000-0000-000000000007';
    const creatorId = '95100000-0000-0000-0000-000000000008';
    late String actionId;

    setUpAll(() async {
      await createTestProfile(conn, creatorId, name: 'Criadora da Dupla');
      await createTestProfile(conn, leavingUser, name: 'Missionária Que Sai');
      actionId = await createAction(
        creatorId,
        futura: true,
        capacity: 2, // a constraint da Dupla exige exatamente 2
        missionaryPair: true,
        visitedGender: 'feminino',
      );
      await confirmAttendance(actionId, leavingUser);
      await deleteAccount(leavingUser);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': creatorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [leavingUser, creatorId]},
      );
      await cleanUpTestUser(conn, creatorId);
    });

    test('o Perfil anonimizado não ocupa mais vaga na Dupla', () async {
      // É o que impede o trigger de composição de ler gênero nulo: quem saiu
      // simplesmente não está mais entre os confirmados de uma Ação futura.
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao '
          'where acao_id = @acao and usuario_id = @uid',
          {'acao': actionId, 'uid': leavingUser},
        ),
        0,
      );
    });
  });

  // ---------------------------------------------------------------------
  // US2 — herança de posse
  // ---------------------------------------------------------------------

  Future<String> createGroup(String ownerId, {String name = 'Grupo de Teste'}) async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, dono_id) "
        "values (@nome, 'Ministério Jovem', @dono) returning id",
      ),
      parameters: {'nome': name, 'dono': ownerId},
    );
    return rows.single.first! as String;
  }

  Future<void> join(String groupId, String userId) async {
    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) '
        'values (@grupo, @usuario) on conflict do nothing',
      ),
      parameters: {'grupo': groupId, 'usuario': userId},
    );
  }

  Future<String> createRound(String groupId, String openedBy, {bool fechada = false}) async {
    // rodadas_votacao_checar_participante lê auth.uid(), não `aberta_por` —
    // sem o claim o fixture roda como postgres e o trigger recusa.
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$openedBy\",\"role\":\"authenticated\"}'",
    );
    final rows = await conn.execute(
      Sql.named(
        "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo, fechada_em) "
        "values (@grupo, @por, now() + interval '7 days', @fechada) returning id",
      ),
      parameters: {
        'grupo': groupId,
        'por': openedBy,
        'fechada': fechada ? DateTime.now().toUtc() : null,
      },
    );
    await conn.execute('reset request.jwt.claims');
    return rows.single.first! as String;
  }

  group('cenários 5 a 11 — herança pelo Administrador mais antigo', () {
    const leavingUser = '95200000-0000-0000-0000-000000000001';
    const member = '95200000-0000-0000-0000-000000000002';
    const adminAntigo = '95200000-0000-0000-0000-000000000003';
    const adminNovo = '95200000-0000-0000-0000-000000000004';
    late String groupId;
    late String openRound;
    late String closedRound;
    late String herAction;

    setUpAll(() async {
      await createTestProfile(conn, adminAntigo, name: 'Admin Mais Antigo');
      await createTestDistrictAdmin(conn, adminAntigo);
      // garante ordem de antiguidade determinística
      await conn.execute(
        Sql.named(
          "update public.administradores_distrito set created_at = now() - interval '1 day' "
          'where usuario_id = @id',
        ),
        parameters: {'id': adminAntigo},
      );
      await createTestProfile(conn, adminNovo, name: 'Admin Mais Novo');
      await createTestDistrictAdmin(conn, adminNovo);

      await createTestProfile(conn, leavingUser, name: 'Dona Que Sai');
      await createTestProfile(conn, member, name: 'Participante Que Fica');

      groupId = await createGroup(leavingUser);
      await join(groupId, member);
      openRound = await createRound(groupId, leavingUser);
      closedRound = await createRound(groupId, leavingUser, fechada: true);
      herAction = await createAction(leavingUser, futura: false);

      // Declaração de Líder dela, confirmada pelo admin; e uma declaração de
      // outra pessoa que ela confirmou.
      await conn.execute(
        Sql.named(
          'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_por, confirmado_em) '
          'values (@grupo, @dela, 2026, @admin, now())',
        ),
        parameters: {'grupo': groupId, 'dela': leavingUser, 'admin': adminAntigo},
      );
      await conn.execute(
        Sql.named(
          'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_por, confirmado_em) '
          'values (@grupo, @outra, 2026, @dela, now())',
        ),
        parameters: {'grupo': groupId, 'outra': member, 'dela': leavingUser},
      );

      await deleteAccount(leavingUser);
    });

    tearDownAll(() async {
      // Escopado aos UUIDs deste arquivo (prefixos 951–954). `dart test` roda os
      // arquivos em paralelo, e um delete sem filtro apaga o arranjo de quem
      // estiver rodando junto — a falha aparece num arquivo que não fez nada.
      await conn.execute(
        "delete from public.liderancas l "
        "where substring(l.usuario_id::text, 1, 3) in ('951','952','953','954') "
        "   or exists (select 1 from public.grupos g "
        "              where g.id = l.grupo_id "
        "                and substring(g.dono_id::text, 1, 3) "
        "                    in ('951','952','953','954'))");
      await conn.execute(
        "delete from public.rodadas_votacao "
        "where substring(aberta_por::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = any(@ids)'),
        parameters: {'ids': [leavingUser, adminAntigo]},
      );
      await conn.execute(
        "delete from public.grupos where substring(dono_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.administradores_distrito "
        "where substring(usuario_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [leavingUser, member, adminAntigo, adminNovo]},
      );
      for (final id in [member, adminAntigo, adminNovo]) {
        await cleanUpTestUser(conn, id);
      }
    });

    test('cenário 5: o Grupo sobrevive sob o Administrador mais antigo', () async {
      final rows = await conn.execute(
        Sql.named('select dono_id from public.grupos where id = @id'),
        parameters: {'id': groupId},
      );
      expect(rows.single.first, adminAntigo);
    });

    test('cenário 5: os participantes originais continuam no Grupo', () async {
      expect(
        await contar(
          'select count(*) from public.participacoes_grupo where grupo_id = @g and usuario_id = @u',
          {'g': groupId, 'u': member},
        ),
        1,
      );
    });

    test('cenário 6: o herdeiro passa a participar do Grupo que recebeu', () async {
      // Se a função trocar dono_id antes de inserir a participação,
      // grupos_dono_deve_participar levanta exceção e a transação inteira
      // desfaz — este teste falha alto, que é o desejado.
      expect(
        await contar(
          'select count(*) from public.participacoes_grupo where grupo_id = @g and usuario_id = @u',
          {'g': groupId, 'u': adminAntigo},
        ),
        1,
      );
    });

    test('cenário 7: a Rodada aberta segue aberta, sob o herdeiro', () async {
      final rows = await conn.execute(
        Sql.named('select aberta_por, fechada_em from public.rodadas_votacao where id = @id'),
        parameters: {'id': openRound},
      );
      expect(rows.single[0], adminAntigo);
      expect(rows.single[1], isNull);
    });

    test('cenário 8: Rodada fechada e Ação criada não trocam de autor', () async {
      final votingRound = await conn.execute(
        Sql.named('select aberta_por from public.rodadas_votacao where id = @id'),
        parameters: {'id': closedRound},
      );
      expect(votingRound.single.first, leavingUser, reason: 'histórico não muda de dono');

      final action = await conn.execute(
        Sql.named('select criador_id from public.acoes where id = @id'),
        parameters: {'id': herAction},
      );
      expect(action.single.first, leavingUser);
    });

    test('cenário 10: a declaração dela some, a que ela confirmou fica', () async {
      expect(
        await contar(
          'select count(*) from public.liderancas where usuario_id = @id',
          {'id': leavingUser},
        ),
        0,
      );
      expect(
        await contar(
          'select count(*) from public.liderancas where confirmado_por = @id',
          {'id': leavingUser},
        ),
        1,
        reason: 'quem ela confirmou continua Líder — é registro de um ato dela',
      );
    });
  });

  group('cenário 9 — voto em Rodada aberta some, em Rodada fechada fica', () {
    const leavingUser = '95300000-0000-0000-0000-000000000001';
    const admin = '95300000-0000-0000-0000-000000000002';
    late String openRound;
    late String closedRound;

    Future<String> createCandidate(String votingRoundId, String groupId, String autorId) async {
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$autorId\",\"role\":\"authenticated\"}'",
      );
      final rows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, grupo_id, rodada_id) "
          "values ('Candidata', now() + interval '10 days', 'Praça', @autor, @grupo, @rodada) "
          'returning id',
        ),
        parameters: {'autor': autorId, 'grupo': groupId, 'rodada': votingRoundId},
      );
      await conn.execute('reset request.jwt.claims');
      return rows.single.first! as String;
    }

    Future<void> vote(String votingRoundId, String userId, String candidateId) async {
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$userId\",\"role\":\"authenticated\"}'",
      );
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': votingRoundId, 'usuario': userId, 'candidata': candidateId},
      );
      await conn.execute('reset request.jwt.claims');
    }

    setUpAll(() async {
      await createTestProfile(conn, admin, name: 'Admin Herdeiro');
      await createTestDistrictAdmin(conn, admin);
      await createTestProfile(conn, leavingUser, name: 'Eleitora Que Sai');

      final groupId = await createGroup(admin, name: 'Grupo com Votação');
      await join(groupId, leavingUser);

      openRound = await createRound(groupId, admin);
      final openCandidate = await createCandidate(openRound, groupId, admin);
      await vote(openRound, leavingUser, openCandidate);

      closedRound = await createRound(groupId, admin);
      final closedCandidate = await createCandidate(closedRound, groupId, admin);
      await vote(closedRound, leavingUser, closedCandidate);
      await conn.execute(
        Sql.named('update public.rodadas_votacao set fechada_em = now() where id = @id'),
        parameters: {'id': closedRound},
      );

      await deleteAccount(leavingUser);
    });

    tearDownAll(() async {
      await conn.execute(
        "delete from public.votos where substring(usuario_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "update public.rodadas_votacao set vencedora_id = null "
        "where substring(aberta_por::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.confirmacoes_acao c using public.acoes a "
        "where c.acao_id = a.id "
        "  and substring(a.criador_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.acoes where substring(criador_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.rodadas_votacao "
        "where substring(aberta_por::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.grupos where substring(dono_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.administradores_distrito "
        "where substring(usuario_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [leavingUser, admin]},
      );
      await cleanUpTestUser(conn, admin);
    });

    test('o voto na Rodada ainda aberta não conta mais', () async {
      expect(
        await contar(
          'select count(*) from public.votos where rodada_id = @r and usuario_id = @u',
          {'r': openRound, 'u': leavingUser},
        ),
        0,
      );
    });

    test('o voto na Rodada já fechada permanece', () async {
      expect(
        await contar(
          'select count(*) from public.votos where rodada_id = @r and usuario_id = @u',
          {'r': closedRound, 'u': leavingUser},
        ),
        1,
        reason: 'faz parte do resultado apurado — é histórico, não intenção',
      );
    });
  });

  group('cenários 11 a 14 — eleição do herdeiro e recusas', () {
    const admin1 = '95400000-0000-0000-0000-000000000001';
    const admin2 = '95400000-0000-0000-0000-000000000002';
    const semNada = '95400000-0000-0000-0000-000000000003';

    setUp(() async {
      await createTestProfile(conn, admin1, name: 'Primeira Administradora');
      await createTestDistrictAdmin(conn, admin1);
      await conn.execute(
        Sql.named(
          "update public.administradores_distrito set created_at = now() - interval '1 day' "
          'where usuario_id = @id',
        ),
        parameters: {'id': admin1},
      );
    });

    tearDown(() async {
      await conn.execute(
        "delete from public.grupos where substring(dono_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        "delete from public.administradores_distrito "
        "where substring(usuario_id::text, 1, 3) in ('951','952','953','954')");
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [admin1, admin2, semNada]},
      );
      for (final id in [admin1, admin2, semNada]) {
        await cleanUpTestUser(conn, id);
      }
    });

    test('cenário 12: a única Administradora é recusada, mesmo com Grupo', () async {
      await createGroup(admin1, name: 'Grupo da Única Admin');
      await expectLater(
        deleteAccount(admin1),
        throwsA(isA<ServerException>()),
      );
      final rows = await conn.execute(
        Sql.named('select anonimizado_em from public.perfis where id = @id'),
        parameters: {'id': admin1},
      );
      expect(rows.single.first, isNull, reason: 'nada pode ter sido alterado');
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': admin1}),
        1,
      );
    });

    test('cenário 13: a única Administradora é recusada mesmo sem nada a herdar', () async {
      // Deliberado: um distrito sem Administrador não consegue promover outro,
      // porque administradores_distrito_checar_regras exige um pré-existente.
      await expectLater(
        deleteAccount(admin1),
        throwsA(isA<ServerException>()),
      );
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': admin1}),
        1,
      );
    });

    test('cenário 11 e 14: com um segundo Administrador, a herança vai pro seguinte', () async {
      await createTestProfile(conn, admin2, name: 'Segunda Administradora');
      await createTestDistrictAdmin(conn, admin2);
      final groupId = await createGroup(admin1, name: 'Grupo da Admin Mais Antiga');

      await deleteAccount(admin1);

      final rows = await conn.execute(
        Sql.named('select dono_id from public.grupos where id = @id'),
        parameters: {'id': groupId},
      );
      expect(rows.single.first, admin2,
          reason: 'quem sai é o mais antigo, então a herança pula pro próximo');
      expect(
        await contar(
          'select count(*) from public.administradores_distrito where usuario_id = @id',
          {'id': admin1},
        ),
        0,
        reason: 'o papel de Administrador de quem saiu deixa de existir',
      );
    });

    test('quem não é Administrador e não tem posse sai normalmente', () async {
      await createTestProfile(conn, semNada, name: 'Usuária Comum');
      await deleteAccount(semNada);
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': semNada}),
        0,
      );
    });
  });
}

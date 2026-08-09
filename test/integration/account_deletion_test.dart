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

  Future<void> comoUsuario(String uid) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
  }

  Future<void> excluirConta(String uid) async {
    await comoUsuario(uid);
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
  Future<String> criarAcao(
    String criadorId, {
    required bool futura,
    int? limiteVagas,
    bool duplaMissionaria = false,
    String? generoVisitado,
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
        'criador': criadorId,
        'limite': limiteVagas,
        'dupla': duplaMissionaria,
        'genero': generoVisitado,
      },
    );
    return rows.single.first! as String;
  }

  Future<void> confirmarPresenca(String acaoId, String usuarioId) async {
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @usuario)',
      ),
      parameters: {'acao': acaoId, 'usuario': usuarioId},
    );
  }

  group('cenário 1 e 2 — anonimização e projeção pública', () {
    const uid = '95100000-0000-0000-0000-000000000001';

    setUpAll(() async {
      await criarPerfilDeTeste(conn, uid, nome: 'Fulana Original');
      await excluirConta(uid);
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
    const criadorId = '95100000-0000-0000-0000-000000000003';
    late String acaoPassada;
    late String acaoFutura;

    setUpAll(() async {
      await criarPerfilDeTeste(conn, criadorId, nome: 'Criadora das Ações');
      await criarPerfilDeTeste(conn, uid, nome: 'Quem Vai Sair');
      acaoPassada = await criarAcao(criadorId, futura: false);
      acaoFutura = await criarAcao(criadorId, futura: true);
      await confirmarPresenca(acaoPassada, uid);
      await confirmarPresenca(acaoFutura, uid);
      await excluirConta(uid);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': criadorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [uid, criadorId]},
      );
      await limparUsuarioDeTeste(conn, criadorId);
    });

    test('a presença na Ação que já aconteceu permanece', () async {
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
          {'acao': acaoPassada, 'uid': uid},
        ),
        1,
      );
    });

    test('a presença na Ação que ainda vai acontecer some', () async {
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
          {'acao': acaoFutura, 'uid': uid},
        ),
        0,
      );
    });
  });

  group('cenário 4 — fila de espera anda sozinha (Princípio IV)', () {
    const donoVaga = '95100000-0000-0000-0000-000000000004';
    const naFila = '95100000-0000-0000-0000-000000000005';
    const criadorId = '95100000-0000-0000-0000-000000000006';
    late String acaoId;

    setUpAll(() async {
      await criarPerfilDeTeste(conn, criadorId, nome: 'Criadora da Lotada');
      await criarPerfilDeTeste(conn, donoVaga, nome: 'Quem Ocupa a Vaga');
      await criarPerfilDeTeste(conn, naFila, nome: 'Quem Espera');
      // limite 2 porque o criador da Ação já nasce confirmado por trigger:
      // com 1 vaga, ela seria dele e ninguém mais ficaria confirmado.
      acaoId = await criarAcao(criadorId, futura: true, limiteVagas: 2);
      await confirmarPresenca(acaoId, donoVaga);
      await confirmarPresenca(acaoId, naFila);
      await excluirConta(donoVaga);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': criadorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [donoVaga, naFila, criadorId]},
      );
      await limparUsuarioDeTeste(conn, naFila);
      await limparUsuarioDeTeste(conn, criadorId);
    });

    test('quem estava na fila foi promovido a confirmado', () async {
      // Nenhuma linha desta feature promove ninguém — quem faz é o trigger
      // confirmacoes_acao_promover_fila, AFTER DELETE, que já existia.
      final rows = await conn.execute(
        Sql.named(
          'select status from public.confirmacoes_acao where acao_id = @acao and usuario_id = @uid',
        ),
        parameters: {'acao': acaoId, 'uid': naFila},
      );
      expect(rows.single.first, 'confirmado');
    });
  });

  group('Dupla Missionária não fica com vaga de quem saiu (Princípio IV)', () {
    const quemSai = '95100000-0000-0000-0000-000000000007';
    const criadorId = '95100000-0000-0000-0000-000000000008';
    late String acaoId;

    setUpAll(() async {
      await criarPerfilDeTeste(conn, criadorId, nome: 'Criadora da Dupla');
      await criarPerfilDeTeste(conn, quemSai, nome: 'Missionária Que Sai');
      acaoId = await criarAcao(
        criadorId,
        futura: true,
        limiteVagas: 2, // a constraint da Dupla exige exatamente 2
        duplaMissionaria: true,
        generoVisitado: 'feminino',
      );
      await confirmarPresenca(acaoId, quemSai);
      await excluirConta(quemSai);
    });

    tearDownAll(() async {
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = @id'),
        parameters: {'id': criadorId},
      );
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [quemSai, criadorId]},
      );
      await limparUsuarioDeTeste(conn, criadorId);
    });

    test('o Perfil anonimizado não ocupa mais vaga na Dupla', () async {
      // É o que impede o trigger de composição de ler gênero nulo: quem saiu
      // simplesmente não está mais entre os confirmados de uma Ação futura.
      expect(
        await contar(
          'select count(*) from public.confirmacoes_acao '
          'where acao_id = @acao and usuario_id = @uid',
          {'acao': acaoId, 'uid': quemSai},
        ),
        0,
      );
    });
  });

  // ---------------------------------------------------------------------
  // US2 — herança de posse
  // ---------------------------------------------------------------------

  Future<String> createGroup(String donoId, {String nome = 'Grupo de Teste'}) async {
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, dono_id) "
        "values (@nome, 'Ministério Jovem', @dono) returning id",
      ),
      parameters: {'nome': nome, 'dono': donoId},
    );
    return rows.single.first! as String;
  }

  Future<void> join(String grupoId, String usuarioId) async {
    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) '
        'values (@grupo, @usuario) on conflict do nothing',
      ),
      parameters: {'grupo': grupoId, 'usuario': usuarioId},
    );
  }

  Future<String> abrirRodada(String grupoId, String abertaPor, {bool fechada = false}) async {
    // rodadas_votacao_checar_participante lê auth.uid(), não `aberta_por` —
    // sem o claim o fixture roda como postgres e o trigger recusa.
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$abertaPor\",\"role\":\"authenticated\"}'",
    );
    final rows = await conn.execute(
      Sql.named(
        "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo, fechada_em) "
        "values (@grupo, @por, now() + interval '7 days', @fechada) returning id",
      ),
      parameters: {
        'grupo': grupoId,
        'por': abertaPor,
        'fechada': fechada ? DateTime.now().toUtc() : null,
      },
    );
    await conn.execute('reset request.jwt.claims');
    return rows.single.first! as String;
  }

  group('cenários 5 a 11 — herança pelo Administrador mais antigo', () {
    const quemSai = '95200000-0000-0000-0000-000000000001';
    const participante = '95200000-0000-0000-0000-000000000002';
    const adminAntigo = '95200000-0000-0000-0000-000000000003';
    const adminNovo = '95200000-0000-0000-0000-000000000004';
    late String grupoId;
    late String rodadaAberta;
    late String rodadaFechada;
    late String acaoDela;

    setUpAll(() async {
      await criarPerfilDeTeste(conn, adminAntigo, nome: 'Admin Mais Antigo');
      await criarAdministradorDistritoDeTeste(conn, adminAntigo);
      // garante ordem de antiguidade determinística
      await conn.execute(
        Sql.named(
          "update public.administradores_distrito set created_at = now() - interval '1 day' "
          'where usuario_id = @id',
        ),
        parameters: {'id': adminAntigo},
      );
      await criarPerfilDeTeste(conn, adminNovo, nome: 'Admin Mais Novo');
      await criarAdministradorDistritoDeTeste(conn, adminNovo);

      await criarPerfilDeTeste(conn, quemSai, nome: 'Dona Que Sai');
      await criarPerfilDeTeste(conn, participante, nome: 'Participante Que Fica');

      grupoId = await createGroup(quemSai);
      await join(grupoId, participante);
      rodadaAberta = await abrirRodada(grupoId, quemSai);
      rodadaFechada = await abrirRodada(grupoId, quemSai, fechada: true);
      acaoDela = await criarAcao(quemSai, futura: false);

      // Declaração de Líder dela, confirmada pelo admin; e uma declaração de
      // outra pessoa que ela confirmou.
      await conn.execute(
        Sql.named(
          'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_por, confirmado_em) '
          'values (@grupo, @dela, 2026, @admin, now())',
        ),
        parameters: {'grupo': grupoId, 'dela': quemSai, 'admin': adminAntigo},
      );
      await conn.execute(
        Sql.named(
          'insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_por, confirmado_em) '
          'values (@grupo, @outra, 2026, @dela, now())',
        ),
        parameters: {'grupo': grupoId, 'outra': participante, 'dela': quemSai},
      );

      await excluirConta(quemSai);
    });

    tearDownAll(() async {
      await conn.execute('delete from public.liderancas');
      await conn.execute('delete from public.rodadas_votacao');
      await conn.execute(
        Sql.named('delete from public.acoes where criador_id = any(@ids)'),
        parameters: {'ids': [quemSai, adminAntigo]},
      );
      await conn.execute('delete from public.grupos');
      await conn.execute('delete from public.administradores_distrito');
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [quemSai, participante, adminAntigo, adminNovo]},
      );
      for (final id in [participante, adminAntigo, adminNovo]) {
        await limparUsuarioDeTeste(conn, id);
      }
    });

    test('cenário 5: o Grupo sobrevive sob o Administrador mais antigo', () async {
      final rows = await conn.execute(
        Sql.named('select dono_id from public.grupos where id = @id'),
        parameters: {'id': grupoId},
      );
      expect(rows.single.first, adminAntigo);
    });

    test('cenário 5: os participantes originais continuam no Grupo', () async {
      expect(
        await contar(
          'select count(*) from public.participacoes_grupo where grupo_id = @g and usuario_id = @u',
          {'g': grupoId, 'u': participante},
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
          {'g': grupoId, 'u': adminAntigo},
        ),
        1,
      );
    });

    test('cenário 7: a Rodada aberta segue aberta, sob o herdeiro', () async {
      final rows = await conn.execute(
        Sql.named('select aberta_por, fechada_em from public.rodadas_votacao where id = @id'),
        parameters: {'id': rodadaAberta},
      );
      expect(rows.single[0], adminAntigo);
      expect(rows.single[1], isNull);
    });

    test('cenário 8: Rodada fechada e Ação criada não trocam de autor', () async {
      final rodada = await conn.execute(
        Sql.named('select aberta_por from public.rodadas_votacao where id = @id'),
        parameters: {'id': rodadaFechada},
      );
      expect(rodada.single.first, quemSai, reason: 'histórico não muda de dono');

      final acao = await conn.execute(
        Sql.named('select criador_id from public.acoes where id = @id'),
        parameters: {'id': acaoDela},
      );
      expect(acao.single.first, quemSai);
    });

    test('cenário 10: a declaração dela some, a que ela confirmou fica', () async {
      expect(
        await contar(
          'select count(*) from public.liderancas where usuario_id = @id',
          {'id': quemSai},
        ),
        0,
      );
      expect(
        await contar(
          'select count(*) from public.liderancas where confirmado_por = @id',
          {'id': quemSai},
        ),
        1,
        reason: 'quem ela confirmou continua Líder — é registro de um ato dela',
      );
    });
  });

  group('cenário 9 — voto em Rodada aberta some, em Rodada fechada fica', () {
    const quemSai = '95300000-0000-0000-0000-000000000001';
    const admin = '95300000-0000-0000-0000-000000000002';
    late String rodadaAberta;
    late String rodadaFechada;

    Future<String> criarCandidata(String rodadaId, String grupoId, String autorId) async {
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$autorId\",\"role\":\"authenticated\"}'",
      );
      final rows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, grupo_id, rodada_id) "
          "values ('Candidata', now() + interval '10 days', 'Praça', @autor, @grupo, @rodada) "
          'returning id',
        ),
        parameters: {'autor': autorId, 'grupo': grupoId, 'rodada': rodadaId},
      );
      await conn.execute('reset request.jwt.claims');
      return rows.single.first! as String;
    }

    Future<void> votar(String rodadaId, String usuarioId, String candidataId) async {
      await conn.execute(
        "set request.jwt.claims to '{\"sub\":\"$usuarioId\",\"role\":\"authenticated\"}'",
      );
      await conn.execute(
        Sql.named(
          'insert into public.votos (rodada_id, usuario_id, candidata_id) '
          'values (@rodada, @usuario, @candidata)',
        ),
        parameters: {'rodada': rodadaId, 'usuario': usuarioId, 'candidata': candidataId},
      );
      await conn.execute('reset request.jwt.claims');
    }

    setUpAll(() async {
      await criarPerfilDeTeste(conn, admin, nome: 'Admin Herdeiro');
      await criarAdministradorDistritoDeTeste(conn, admin);
      await criarPerfilDeTeste(conn, quemSai, nome: 'Eleitora Que Sai');

      final grupoId = await createGroup(admin, nome: 'Grupo com Votação');
      await join(grupoId, quemSai);

      rodadaAberta = await abrirRodada(grupoId, admin);
      final candidataAberta = await criarCandidata(rodadaAberta, grupoId, admin);
      await votar(rodadaAberta, quemSai, candidataAberta);

      rodadaFechada = await abrirRodada(grupoId, admin);
      final candidataFechada = await criarCandidata(rodadaFechada, grupoId, admin);
      await votar(rodadaFechada, quemSai, candidataFechada);
      await conn.execute(
        Sql.named('update public.rodadas_votacao set fechada_em = now() where id = @id'),
        parameters: {'id': rodadaFechada},
      );

      await excluirConta(quemSai);
    });

    tearDownAll(() async {
      await conn.execute('delete from public.votos');
      await conn.execute('delete from public.acoes');
      await conn.execute('delete from public.rodadas_votacao');
      await conn.execute('delete from public.grupos');
      await conn.execute('delete from public.administradores_distrito');
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [quemSai, admin]},
      );
      await limparUsuarioDeTeste(conn, admin);
    });

    test('o voto na Rodada ainda aberta não conta mais', () async {
      expect(
        await contar(
          'select count(*) from public.votos where rodada_id = @r and usuario_id = @u',
          {'r': rodadaAberta, 'u': quemSai},
        ),
        0,
      );
    });

    test('o voto na Rodada já fechada permanece', () async {
      expect(
        await contar(
          'select count(*) from public.votos where rodada_id = @r and usuario_id = @u',
          {'r': rodadaFechada, 'u': quemSai},
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
      await criarPerfilDeTeste(conn, admin1, nome: 'Primeira Administradora');
      await criarAdministradorDistritoDeTeste(conn, admin1);
      await conn.execute(
        Sql.named(
          "update public.administradores_distrito set created_at = now() - interval '1 day' "
          'where usuario_id = @id',
        ),
        parameters: {'id': admin1},
      );
    });

    tearDown(() async {
      await conn.execute('delete from public.grupos');
      await conn.execute('delete from public.administradores_distrito');
      await conn.execute(
        Sql.named('delete from public.perfis where id = any(@ids)'),
        parameters: {'ids': [admin1, admin2, semNada]},
      );
      for (final id in [admin1, admin2, semNada]) {
        await limparUsuarioDeTeste(conn, id);
      }
    });

    test('cenário 12: a única Administradora é recusada, mesmo com Grupo', () async {
      await createGroup(admin1, nome: 'Grupo da Única Admin');
      await expectLater(
        excluirConta(admin1),
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
        excluirConta(admin1),
        throwsA(isA<ServerException>()),
      );
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': admin1}),
        1,
      );
    });

    test('cenário 11 e 14: com um segundo Administrador, a herança vai pro seguinte', () async {
      await criarPerfilDeTeste(conn, admin2, nome: 'Segunda Administradora');
      await criarAdministradorDistritoDeTeste(conn, admin2);
      final grupoId = await createGroup(admin1, nome: 'Grupo da Admin Mais Antiga');

      await excluirConta(admin1);

      final rows = await conn.execute(
        Sql.named('select dono_id from public.grupos where id = @id'),
        parameters: {'id': grupoId},
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
      await criarPerfilDeTeste(conn, semNada, nome: 'Usuária Comum');
      await excluirConta(semNada);
      expect(
        await contar('select count(*) from auth.users where id = @id', {'id': semNada}),
        0,
      );
    });
  });
}

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
}

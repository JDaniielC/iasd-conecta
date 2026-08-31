import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 021 — visibilidade do voto.
///
/// A promessa: só a própria pessoa lê em quem ela votou. Antes desta feature a
/// política era `votos_select_public ... using (true)`, e com o grant de `anon`
/// isso significava que qualquer pessoa da internet lia a tabela inteira — que
/// é o par nominal (usuario_id, candidata_id), não um agregado.
///
/// Esconder na tela não é proteger, então a prova precisa falar com o banco, e
/// não com widget. É o que este arquivo faz.
///
/// O caso `(f)` é o mais importante e o menos óbvio: ele existe porque ESTA
/// feature arma uma dependência que antes dela era inofensiva. Enquanto a
/// leitura era aberta, tanto fazia `fechar_rodada_se_devido` ser
/// `security definer` ou `invoker` — todo mundo enxergava todos os votos, e a
/// contagem saía igual. Depois de fechar a leitura, virar `invoker` faz a
/// apuração contar só os votos de quem chamou, eleger a candidata dessa pessoa,
/// e APAGAR as perdedoras. Sem erro e sem rastro.
///
/// Por isso o `(f)` é montado com quem fecha a Rodada tendo votado na candidata
/// PERDEDORA. Montado ao contrário, ele passa verde numa apuração quebrada.

const _uidVoterMajorityA = '81000000-0000-0000-0000-000000000001';
const _uidVoterMajorityB = '81000000-0000-0000-0000-000000000002';
const _uidVoterMinority = '81000000-0000-0000-0000-000000000003';
const _uidOutsider = '81000000-0000-0000-0000-000000000004';

/// Visitante: pessoa sem cadastro, e por isso FORA de `_allUids` — aquela lista
/// cria Perfil para cada uid, e Visitante é justamente quem não tem.
const _uidVisitor = '81000000-0000-0000-0000-0000000000f0';

const _allUids = [
  _uidVoterMajorityA,
  _uidVoterMajorityB,
  _uidVoterMinority,
  _uidOutsider,
];

/// Executa [action] com a identidade de [uid], como o PostgREST faria.
///
/// Sem isto os testes rodariam como `postgres`, que é dono das tabelas e
/// ignora RLS — provando exatamente nada.
/// Executa [action] como Visitante: pessoa sem cadastro, COM sessão.
///
/// Era uma cópia local que fazia `set role anon`, e estava errada de duas
/// formas — o papel (o app coloca todo Visitante em sessão anônima, logo
/// `authenticated`) e o fato de ser a terceira cópia da mesma ideia. Delega ao
/// helper compartilhado, que é o único lugar onde cada papel se define.
Future<void> _asVisitor(Connection conn, Future<void> Function() action) =>
    asVisitor(conn, _uidVisitor, action);

/// Quantos votos a identidade corrente enxerga.
Future<int> _visibleVoteCount(Connection conn) async {
  final r = await conn.execute('select count(*) from public.votos');
  return (r.first[0] as int);
}

/// Cria um Grupo com os quatro Usuários dentro, menos o Outsider.
Future<String> _createGroup(Connection conn, {required String ownerId}) async {
  final r = await conn.execute(
    Sql.named(
      "insert into public.grupos (nome, categoria, dono_id) "
      "values ('Grupo de teste 021', 'Estudo bíblico', @owner) returning id",
    ),
    parameters: {'owner': ownerId},
  );
  final groupId = r.first[0] as String;
  // O dono já entra por trigger; os demais entram aqui. O Outsider fica fora
  // de propósito — é o caso (b).
  await conn.execute(
    Sql.named(
      'insert into public.participacoes_grupo (grupo_id, usuario_id) '
      'values (@g, @u1), (@g, @u2) on conflict do nothing',
    ),
    parameters: {
      'g': groupId,
      'u1': _uidVoterMajorityB,
      'u2': _uidVoterMinority,
    },
  );
  return groupId;
}

/// Abre uma Rodada com prazo no futuro, como quem a abre de verdade faria.
Future<String> _openRound(
  Connection conn, {
  required String groupId,
  required String openedBy,
}) async {
  late String roundId;
  await asUser(conn, openedBy, () async {
    final r = await conn.execute(
      Sql.named(
        'insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) '
        "values (@g, @u, now() + interval '7 days') returning id",
      ),
      parameters: {'g': groupId, 'u': openedBy},
    );
    roundId = r.first[0] as String;
  });
  return roundId;
}

Future<String> _addCandidate(
  Connection conn, {
  required String groupId,
  required String roundId,
  required String creatorId,
  required String name,
}) async {
  late String candidateId;
  await asUser(conn, creatorId, () async {
    final r = await conn.execute(
      Sql.named(
        'insert into public.acoes '
        '(nome, data_hora, local, criador_id, confirmada, grupo_id, rodada_id) '
        "values (@n, now() + interval '10 days', 'Centro', @c, false, @g, @r) "
        'returning id',
      ),
      parameters: {'n': name, 'c': creatorId, 'g': groupId, 'r': roundId},
    );
    candidateId = r.first[0] as String;
  });
  return candidateId;
}

/// Vota como [uid] pelo mesmo caminho do app: `upsert` com conflito na chave
/// (rodada_id, usuario_id) — ver `voting_round_repository.dart:72-75`.
Future<void> _vote(
  Connection conn, {
  required String uid,
  required String roundId,
  required String candidateId,
}) async {
  await asUser(conn, uid, () async {
    await conn.execute(
      Sql.named(
        'insert into public.votos (rodada_id, usuario_id, candidata_id) '
        'values (@r, @u, @c) '
        'on conflict (rodada_id, usuario_id) '
        'do update set candidata_id = excluded.candidata_id',
      ),
      parameters: {'r': roundId, 'u': uid, 'c': candidateId},
    );
  });
}

/// Empurra o prazo para o passado, para que qualquer participante possa fechar
/// a Rodada sem ser o Dono do Grupo.
///
/// `p_forcar = true` só funciona para o Dono (`rodada_votacao.sql:158-163`), e
/// o caso (f) precisa que quem fecha seja justamente quem NÃO é dono e votou na
/// perdedora. Vencer o prazo é o caminho honesto para isso.
Future<void> _expireRound(Connection conn, String roundId) async {
  await conn.execute(
    Sql.named(
      "update public.rodadas_votacao set prazo = now() - interval '1 hour' "
      'where id = @r',
    ),
    parameters: {'r': roundId},
  );
}

Future<void> _closeRound(
  Connection conn, {
  required String roundId,
  required String calledBy,
}) async {
  await asUser(conn, calledBy, () async {
    await conn.execute(
      Sql.named('select public.fechar_rodada_se_devido(@r, false)'),
      parameters: {'r': roundId},
    );
  });
}

Future<String?> _winnerOf(Connection conn, String roundId) async {
  final r = await conn.execute(
    Sql.named('select vencedora_id from public.rodadas_votacao where id = @r'),
    parameters: {'r': roundId},
  );
  return r.first[0] as String?;
}

/// Apaga só o que ESTE arquivo criou.
///
/// A primeira versão apagava `public.votos`, `acoes` e `grupos` inteiros — e
/// `dart test` roda os arquivos em paralelo, então isso derrubava sete testes de
/// outras features no meio da execução delas. Limpeza de teste precisa ser tão
/// escopada quanto a escrita que ela desfaz.
Future<void> _cleanUpOwnData(Connection conn) async {
  const uids = _allUids;
  await conn.execute(
    Sql.named('delete from public.votos where usuario_id = any(@u)'),
    parameters: {'u': uids},
  );
  // vencedora_id aponta para acoes, então precisa soltar antes de apagar.
  await conn.execute(
    Sql.named(
      'update public.rodadas_votacao set vencedora_id = null '
      'where aberta_por = any(@u)',
    ),
    parameters: {'u': uids},
  );
  await conn.execute(
    Sql.named('delete from public.acoes where criador_id = any(@u)'),
    parameters: {'u': uids},
  );
  await conn.execute(
    Sql.named('delete from public.rodadas_votacao where aberta_por = any(@u)'),
    parameters: {'u': uids},
  );
  await conn.execute(
    Sql.named('delete from public.grupos where dono_id = any(@u)'),
    parameters: {'u': uids},
  );
}

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestUser(conn, uid);
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }
    await createTestVisitor(conn, _uidVisitor);
  });

  setUp(() async {
    await _cleanUpOwnData(conn);
  });

  tearDownAll(() async {
    await _cleanUpOwnData(conn);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await cleanUpTestUser(conn, _uidVisitor);
    await conn.close();
  });

  /// Monta uma Rodada com maioria em X e minoria em Y.
  Future<({String roundId, String candidateX, String candidateY})>
  buildContestedRound() async {
    final groupId = await _createGroup(conn, ownerId: _uidVoterMajorityA);
    final roundId = await _openRound(
      conn,
      groupId: groupId,
      openedBy: _uidVoterMajorityA,
    );
    final candidateX = await _addCandidate(
      conn,
      groupId: groupId,
      roundId: roundId,
      creatorId: _uidVoterMajorityA,
      name: 'Visita ao asilo',
    );
    final candidateY = await _addCandidate(
      conn,
      groupId: groupId,
      roundId: roundId,
      creatorId: _uidVoterMinority,
      name: 'Entrega de cestas',
    );
    await _vote(
      conn,
      uid: _uidVoterMajorityA,
      roundId: roundId,
      candidateId: candidateX,
    );
    await _vote(
      conn,
      uid: _uidVoterMajorityB,
      roundId: roundId,
      candidateId: candidateX,
    );
    await _vote(
      conn,
      uid: _uidVoterMinority,
      roundId: roundId,
      candidateId: candidateY,
    );
    return (roundId: roundId, candidateX: candidateX, candidateY: candidateY);
  }

  test('(a) Visitante sem cadastro não lê voto nenhum (FR-001)', () async {
    await buildContestedRound();

    late int seen;
    await _asVisitor(conn, () async {
      // Precisa devolver conjunto vazio, NÃO erro de permissão: a diferença
      // entre "não há votos" e "não posso ver" seria um canal lateral que
      // conta quantos votos existem escondidos.
      seen = await _visibleVoteCount(conn);
    });

    expect(seen, 0, reason: 'Visitante não pode ler voto de ninguém');
  });

  test('(b) Usuário de fora do Grupo não lê voto nenhum (FR-002)', () async {
    await buildContestedRound();

    late int seen;
    await asUser(conn, _uidOutsider, () async {
      seen = await _visibleVoteCount(conn);
    });

    expect(seen, 0, reason: 'quem não participa do Grupo não lê os votos dele');
  });

  test('(c) participante lê o próprio voto e só ele, mesmo com 3 votos na '
      'Rodada (FR-003, FR-004)', () async {
    final round = await buildContestedRound();

    late List<List<dynamic>> rows;
    await asUser(conn, _uidVoterMinority, () async {
      final r = await conn.execute(
        'select usuario_id, candidata_id from public.votos',
      );
      rows = r.map((row) => row.toList()).toList();
    });

    // O ponto do caso: o filtro não é "tudo ou nada". Ela vê 1 de 3.
    expect(rows.length, 1, reason: 'só a própria linha');
    expect(rows.first[0], _uidVoterMinority);
    expect(
      rows.first[1],
      round.candidateY,
      reason: 'e com a candidata certa, não uma linha qualquer',
    );
  });

  test(
    '(d) a restrição continua valendo depois que a Rodada fecha (FR-006)',
    () async {
      final round = await buildContestedRound();
      await _expireRound(conn, round.roundId);
      await _closeRound(
        conn,
        roundId: round.roundId,
        calledBy: _uidVoterMajorityA,
      );

      // Depois de fechar, as perdedoras são apagadas e sobram justamente os
      // votos da vencedora — ou seja, o que resta legível identificaria quem
      // NÃO votou nela, por ausência.
      late int seenByVisitor;
      late int seenByOutsider;
      await _asVisitor(conn, () async {
        seenByVisitor = await _visibleVoteCount(conn);
      });
      await asUser(conn, _uidOutsider, () async {
        seenByOutsider = await _visibleVoteCount(conn);
      });

      expect(seenByVisitor, 0);
      expect(seenByOutsider, 0);
    },
  );

  test('(e) votar pela primeira vez continua funcionando (FR-007)', () async {
    final groupId = await _createGroup(conn, ownerId: _uidVoterMajorityA);
    final roundId = await _openRound(
      conn,
      groupId: groupId,
      openedBy: _uidVoterMajorityA,
    );
    final candidate = await _addCandidate(
      conn,
      groupId: groupId,
      roundId: roundId,
      creatorId: _uidVoterMajorityA,
      name: 'Visita ao asilo',
    );

    await _vote(
      conn,
      uid: _uidVoterMajorityB,
      roundId: roundId,
      candidateId: candidate,
    );

    final r = await conn.execute(
      Sql.named('select count(*) from public.votos where usuario_id = @u'),
      parameters: {'u': _uidVoterMajorityB},
    );
    expect(r.first[0], 1);
  });

  test('(f) a apuração conta TODOS os votos, não só os de quem fecha a '
      'Rodada (FR-009)', () async {
    // A montagem é o teste. Quem chama fechar_rodada_se_devido é
    // _uidVoterMinority, que votou na PERDEDORA. Se a apuração passar a
    // enxergar só os votos de quem chamou, a vencedora vira a candidata Y —
    // e este expect pega. Montar ao contrário não pegaria nada.
    final round = await buildContestedRound();
    await _expireRound(conn, round.roundId);
    await _closeRound(
      conn,
      roundId: round.roundId,
      calledBy: _uidVoterMinority,
    );

    expect(
      await _winnerOf(conn, round.roundId),
      round.candidateX,
      reason:
          'a candidata com 2 votos vence, mesmo quem fechou a Rodada '
          'tendo votado na outra — se falhou aqui, fechar_rodada_se_devido '
          'deixou de rodar fora da RLS e está contando só o voto de quem a '
          'chamou',
    );
  });

  test('(g) trocar de voto substitui o anterior; só a última escolha conta '
      '(FR-008)', () async {
    final round = await buildContestedRound();

    // A pessoa muda de ideia, pelo mesmo upsert que o app usa — agora com a
    // leitura fechada. Este era o risco que a spec apontava como principal.
    await _vote(
      conn,
      uid: _uidVoterMinority,
      roundId: round.roundId,
      candidateId: round.candidateX,
    );

    final r = await conn.execute(
      Sql.named('select candidata_id from public.votos where usuario_id = @u'),
      parameters: {'u': _uidVoterMinority},
    );
    expect(r.length, 1, reason: 'uma linha por pessoa por Rodada, não duas');
    expect(r.first[0], round.candidateX, reason: 'só a última escolha conta');
  });

  test(
    '(h) ninguém sobrescreve o voto de outra pessoa (FR-004, escrita)',
    () async {
      final round = await buildContestedRound();

      // Fechar a leitura não pode ter afrouxado a escrita.
      await expectLater(
        asUser(conn, _uidOutsider, () async {
          await conn.execute(
            Sql.named(
              'insert into public.votos (rodada_id, usuario_id, candidata_id) '
              'values (@r, @u, @c) '
              'on conflict (rodada_id, usuario_id) '
              'do update set candidata_id = excluded.candidata_id',
            ),
            parameters: {
              'r': round.roundId,
              'u': _uidVoterMinority,
              'c': round.candidateX,
            },
          );
        }),
        throwsA(isA<Exception>()),
      );

      // E o voto da vítima continua como estava.
      final r = await conn.execute(
        Sql.named(
          'select candidata_id from public.votos where usuario_id = @u',
        ),
        parameters: {'u': _uidVoterMinority},
      );
      expect(r.first[0], round.candidateY);
    },
  );

  test('(i) empate é resolvido por sorteio, e só uma vence (FR-011)', () async {
    final groupId = await _createGroup(conn, ownerId: _uidVoterMajorityA);
    final roundId = await _openRound(
      conn,
      groupId: groupId,
      openedBy: _uidVoterMajorityA,
    );
    final candidateX = await _addCandidate(
      conn,
      groupId: groupId,
      roundId: roundId,
      creatorId: _uidVoterMajorityA,
      name: 'Visita ao asilo',
    );
    final candidateY = await _addCandidate(
      conn,
      groupId: groupId,
      roundId: roundId,
      creatorId: _uidVoterMinority,
      name: 'Entrega de cestas',
    );
    await _vote(
      conn,
      uid: _uidVoterMajorityA,
      roundId: roundId,
      candidateId: candidateX,
    );
    await _vote(
      conn,
      uid: _uidVoterMinority,
      roundId: roundId,
      candidateId: candidateY,
    );

    await _expireRound(conn, roundId);
    await _closeRound(conn, roundId: roundId, calledBy: _uidVoterMajorityA);

    // Não se exige QUAL vence: o desempate é `random()` por desenho
    // (`rodada_votacao.sql:174`), e um teste que exigisse uma específica ficaria
    // intermitente e acabaria desativado.
    final winner = await _winnerOf(conn, roundId);
    expect(winner, anyOf(candidateX, candidateY));

    final remaining = await conn.execute(
      Sql.named('select count(*) from public.acoes where rodada_id = @r'),
      parameters: {'r': roundId},
    );
    expect(remaining.first[0], 1, reason: 'a perdedora é descartada');
  });
}

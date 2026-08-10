import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// SC-005 — **nenhum caminho de exclusão deixa arquivo para trás.**
///
/// Este é o teste central da feature 013, e existe porque órfão **não tem
/// sintoma**: não aparece em tela, não quebra nada, não levanta exceção. É
/// dado pessoal retido sem finalidade (Princípio II) que ninguém descobre
/// olhando o app.
///
/// **O que este teste afirma, e por que não é "contar arquivos no bucket".**
/// A tarefa original pedia contar objetos antes e depois. Contar
/// `storage.objects` por SQL daria um teste que **sempre passa e nunca prova
/// nada**: a documentação do fornecedor (research D-004) diz literalmente que
/// *"deleting objects via a SQL query will not remove the object from the
/// bucket and will result in the object being orphaned"* — apagar a linha por
/// SQL não apaga o binário de qualquer jeito. Um verde ali seria falso.
///
/// O que de fato garante SC-005 é a **fila**: se todo caminho de exclusão
/// enfileira o caminho do arquivo, a drenagem alcança todos. Um caminho que
/// não enfileira é o órfão, e ele fica visível como ausência na fila. Por isso
/// as asserções são sobre `public.capas_a_remover`.
///
/// Os três caminhos cobertos aqui são os que passam por SQL. O quarto —
/// exclusão de conta — está em `foto_capa_exclusao_conta_test.dart`.
const _uidOwner = '7c000000-0000-0000-0000-000000000001';
const _uidVoter = '7c000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;
  late Object groupId;

  Future<void> asUser(String uid, Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
    }
  }

  /// A fila conhece este caminho e ele ainda não foi drenado?
  Future<bool> isQueued(String path) async {
    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.capas_a_remover '
        'where caminho = @caminho and removido_em is null',
      ),
      parameters: {'caminho': path},
    );
    return (rows.single.toColumnMap()['total'] as int) == 1;
  }

  Future<int> coverCountFor(String column, Object id) async {
    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.fotos_capa where $column = @id'),
      parameters: {'id': id},
    );
    return rows.single.toColumnMap()['total'] as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono FotoCapaOrfao');
    await createTestProfile(conn, _uidVoter, name: 'Votante FotoCapaOrfao');

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo FotoCapaOrfao', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @votante)',
      ),
      parameters: {'grupo': groupId, 'votante': _uidVoter},
    );
  });

  tearDownAll(() async {
    // Limpeza escopada aos MEUS dados. `dart test` roda os arquivos em
    // paralelo, e delete sem filtro neste projeto já foi causa raiz de falha
    // intermitente em arquivos que não tinham feito nada errado (feature 014).
    await conn.execute(
      Sql.named(
        'delete from public.capas_a_remover where caminho like @prefixo',
      ),
      parameters: {'prefixo': 'grupo/$groupId/%'},
    );
    await conn.execute(
      Sql.named(
        'delete from public.capas_a_remover where caminho like @prefixo',
      ),
      parameters: {'prefixo': 'acao/%-orfao-%'},
    );
    await conn.execute(
      Sql.named('update public.rodadas_votacao set vencedora_id = null where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    // As Ações avulsas dos casos (d) e (e) não caem no delete por Grupo.
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @dono'),
      parameters: {'dono': _uidOwner},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidVoter);
    await conn.close();
  });

  test('(a) SC-005: remoção manual enfileira o arquivo', () async {
    final path = 'grupo/$groupId/manual.jpg';

    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
          'values (@grupo, @caminho, @dono)',
        ),
        parameters: {'grupo': groupId, 'caminho': path, 'dono': _uidOwner},
      );
    });
    expect(await isQueued(path), isFalse,
        reason: 'capa recém-criada não pode nascer na fila de remoção');

    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('delete from public.fotos_capa where caminho = @caminho'),
        parameters: {'caminho': path},
      );
    });

    expect(await isQueued(path), isTrue);
    expect(await coverCountFor('grupo_id', groupId), 0);
  });

  test('(b) SC-005: trocar a capa enfileira a ANTIGA e só ela', () async {
    final oldPath = 'grupo/$groupId/antiga.jpg';
    final newPath = 'grupo/$groupId/nova.jpg';

    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
          'values (@grupo, @caminho, @dono)',
        ),
        parameters: {'grupo': groupId, 'caminho': oldPath, 'dono': _uidOwner},
      );

      // Trocar é DELETE + INSERT, nunca UPDATE do caminho — não existe policy
      // de update, de propósito. Um UPDATE deixaria o arquivo antigo órfão sem
      // nenhum aviso, e é exatamente o que este caso prova que não acontece.
      await conn.execute(
        Sql.named('delete from public.fotos_capa where caminho = @caminho'),
        parameters: {'caminho': oldPath},
      );
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
          'values (@grupo, @caminho, @dono)',
        ),
        parameters: {'grupo': groupId, 'caminho': newPath, 'dono': _uidOwner},
      );
    });

    expect(await isQueued(oldPath), isTrue);
    expect(await isQueued(newPath), isFalse,
        reason: 'a capa em uso não pode entrar na fila de remoção');
    expect(await coverCountFor('grupo_id', groupId), 1);

    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named('delete from public.fotos_capa where caminho = @caminho'),
        parameters: {'caminho': newPath},
      );
    });
  });

  test(
    '(c) SC-005: candidata perdedora descartada leva a capa junto — o caminho '
    'que não passa por tela nenhuma',
    () async {
      // Este é o caso mais importante da feature. `fechar_rodada_se_devido`
      // apaga as perdedoras com `delete from public.acoes`
      // (20260724084300_rodada_votacao.sql:178), dentro do banco, sem nenhuma
      // tela envolvida. Se a remoção do arquivo morasse no cliente, ESTE
      // caminho nunca apagaria arquivo — e ninguém perceberia.
      late Object roundId;
      late Object winner;
      late Object loser;

      await asUser(_uidOwner, () async {
        final roundRows = await conn.execute(
          Sql.named(
            "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
            "values (@grupo, @dono, now() + interval '1 day') returning id",
          ),
          parameters: {'grupo': groupId, 'dono': _uidOwner},
        );
        roundId = roundRows.single.toColumnMap()['id']!;

        final winnerRows = await conn.execute(
          Sql.named(
            "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
            "values ('Candidata Vencedora Orfao', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
          ),
          parameters: {'dono': _uidOwner, 'rodada': roundId},
        );
        winner = winnerRows.single.toColumnMap()['id']!;

        final loserRows = await conn.execute(
          Sql.named(
            "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
            "values ('Candidata Perdedora Orfao', now() + interval '6 days', 'Praça', @dono, @rodada) returning id",
          ),
          parameters: {'dono': _uidOwner, 'rodada': roundId},
        );
        loser = loserRows.single.toColumnMap()['id']!;
      });

      final loserPath = 'acao/$loser/perdedora-orfao-capa.jpg';
      final winnerPath = 'acao/$winner/vencedora-orfao-capa.jpg';

      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named(
            'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
            'values (@acao, @caminho, @dono)',
          ),
          parameters: {'acao': loser, 'caminho': loserPath, 'dono': _uidOwner},
        );
        await conn.execute(
          Sql.named(
            'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
            'values (@acao, @caminho, @dono)',
          ),
          parameters: {'acao': winner, 'caminho': winnerPath, 'dono': _uidOwner},
        );
      });

      await asUser(_uidVoter, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@rodada, @usuario, @candidata)',
          ),
          parameters: {
            'rodada': roundId,
            'usuario': _uidVoter,
            'candidata': winner,
          },
        );
      });

      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
          parameters: {'rodada': roundId},
        );
      });

      // A perdedora sumiu, e com ela a linha da capa — por cascade.
      expect(await coverCountFor('acao_id', loser), 0);
      expect(await isQueued(loserPath), isTrue,
          reason: 'cascade tem de disparar o gatilho e enfileirar o arquivo');

      // A vencedora vira a Ação confirmada e mantém a capa.
      expect(await coverCountFor('acao_id', winner), 1);
      expect(await isQueued(winnerPath), isFalse);

      await conn.execute(
        Sql.named('update public.rodadas_votacao set vencedora_id = null where id = @rodada'),
        parameters: {'rodada': roundId},
      );
      await conn.execute(
        Sql.named('delete from public.fotos_capa where acao_id = @acao'),
        parameters: {'acao': winner},
      );
    },
  );

  test('(d) FR-022: cancelar a Ação apaga a capa — não há cascade que dispare',
      () async {
    // Cancelar é `update acoes set cancelada_em`: a LINHA DA AÇÃO NÃO SOME.
    // Sem gatilho explícito, a imagem de uma Ação cancelada ficaria pública
    // para sempre e ninguém perceberia — a Ação some das listas, a imagem não.
    late Object actionId;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          // Ação AVULSA: o domínio recusa Ação de Grupo que não seja
          // candidata de uma Rodada, e essa regra não é desta feature.
          "insert into public.acoes (nome, data_hora, local, criador_id, confirmada) "
          "values ('Ação a Cancelar Orfao', now() + interval '5 days', 'Sede', @dono, true) returning id",
        ),
        parameters: {'dono': _uidOwner},
      );
      actionId = rows.single.toColumnMap()['id']!;
    });

    final path = 'acao/$actionId/cancelada-orfao-capa.jpg';
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
          'values (@acao, @caminho, @dono)',
        ),
        parameters: {'acao': actionId, 'caminho': path, 'dono': _uidOwner},
      );
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @id'),
        parameters: {'id': actionId},
      );
    });

    expect(await coverCountFor('acao_id', actionId), 0);
    expect(await isQueued(path), isTrue);

    // A Ação continua existindo — cancelar não apaga a Ação.
    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.acoes where id = @id'),
      parameters: {'id': actionId},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });

  test('(e) FR-023: Ação encerrada por tempo MANTÉM a capa — é histórico',
      () async {
    // A diferença entre encerrada e cancelada é deliberada. Encerrada
    // aconteceu, tem presenças registradas, e a capa faz parte do registro.
    // Cancelada é o contrário: não aconteceu.
    late Object actionId;
    await asUser(_uidOwner, () async {
      final rows = await conn.execute(
        Sql.named(
          // Ação AVULSA e no FUTURO: criar Ação já passada é recusado pela
          // RLS de confirmacoes_acao, porque criar confirma o criador
          // automaticamente e ninguém confirma presença no que já passou.
          // O tempo é empurrado para trás logo abaixo.
          "insert into public.acoes (nome, data_hora, local, criador_id, confirmada) "
          "values ('Ação Encerrada Orfao', now() + interval '5 days', 'Sede', @dono, true) returning id",
        ),
        parameters: {'dono': _uidOwner},
      );
      actionId = rows.single.toColumnMap()['id']!;
    });

    // Encerrar é passagem do tempo, e o tempo não se acelera num teste: a
    // data é movida para o passado direto no banco, sem papel de aplicação.
    await conn.execute(
      Sql.named(
        "update public.acoes set data_hora = now() - interval '5 days' where id = @id",
      ),
      parameters: {'id': actionId},
    );

    final path = 'acao/$actionId/encerrada-orfao-capa.jpg';
    await asUser(_uidOwner, () async {
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
          'values (@acao, @caminho, @dono)',
        ),
        parameters: {'acao': actionId, 'caminho': path, 'dono': _uidOwner},
      );
    });

    // Encerrar é passagem do tempo: nada é executado, nada muda na linha.
    expect(await coverCountFor('acao_id', actionId), 1);
    expect(await isQueued(path), isFalse);

    await conn.execute(
      Sql.named('delete from public.fotos_capa where acao_id = @id'),
      parameters: {'id': actionId},
    );
  });

  test(
    '(f) FR-019: denúncias pendentes são encerradas quando a imagem some, '
    'por qualquer caminho',
    () async {
      // Sem isto, o Administrador acumula pendências sobre imagens que não
      // existem mais, e a lista perde credibilidade em poucas semanas.
      final path = 'grupo/$groupId/denunciada.jpg';
      late Object photoId;

      await asUser(_uidOwner, () async {
        final rows = await conn.execute(
          Sql.named(
            'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
            'values (@grupo, @caminho, @dono) returning id',
          ),
          parameters: {'grupo': groupId, 'caminho': path, 'dono': _uidOwner},
        );
        photoId = rows.single.toColumnMap()['id']!;
      });

      // Denúncia de Visitante SEM Perfil — o caso que a feature existe para
      // atender (FR-015).
      await conn.execute('set role anon');
      try {
        await conn.execute(
          Sql.named(
            'insert into public.denuncias_imagem (foto_id, motivo) '
            "values (@foto, 'Aparece uma criança')",
          ),
          parameters: {'foto': photoId},
        );
      } finally {
        await conn.execute('reset role');
      }

      final before = await conn.execute(
        Sql.named(
          'select count(*) as total from public.denuncias_imagem where foto_id = @f',
        ),
        parameters: {'f': photoId},
      );
      expect(before.single.toColumnMap()['total'], 1);

      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named('delete from public.fotos_capa where id = @id'),
          parameters: {'id': photoId},
        );
      });

      final after = await conn.execute(
        Sql.named(
          'select count(*) as total from public.denuncias_imagem where foto_id = @f',
        ),
        parameters: {'f': photoId},
      );
      expect(after.single.toColumnMap()['total'], 0,
          reason: 'o cascade de foto_id é o encerramento automático de FR-019');
      expect(await isQueued(path), isTrue);
    },
  );

  test(
    '(g) FR-013/FR-026/SC-009: remover a capa não altera NADA além dela',
    () async {
      // O contrário do teste de órfão: lá se prova que a capa some; aqui, que
      // só ela some. Sem isto, "remover capa" poderia estar levando presença
      // ou voto junto e os outros testes continuariam verdes — eles contam
      // capas e fila, não o resto.
      late Object roundId;
      late Object candidateId;

      await asUser(_uidOwner, () async {
        final roundRows = await conn.execute(
          Sql.named(
            "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
            "values (@grupo, @dono, now() + interval '1 day') returning id",
          ),
          parameters: {'grupo': groupId, 'dono': _uidOwner},
        );
        roundId = roundRows.single.toColumnMap()['id']!;

        final candidateRows = await conn.execute(
          Sql.named(
            "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
            "values ('Candidata Intacta', now() + interval '5 days', 'Sede', @dono, @rodada) returning id",
          ),
          parameters: {'dono': _uidOwner, 'rodada': roundId},
        );
        candidateId = candidateRows.single.toColumnMap()['id']!;
      });

      await asUser(_uidVoter, () async {
        await conn.execute(
          Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) '
            'values (@acao, @usuario)',
          ),
          parameters: {'acao': candidateId, 'usuario': _uidVoter},
        );
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@rodada, @usuario, @candidata)',
          ),
          parameters: {
            'rodada': roundId,
            'usuario': _uidVoter,
            'candidata': candidateId,
          },
        );
      });

      Future<Map<String, int>> snapshot() async {
        final rows = await conn.execute(
          Sql.named(
            'select '
            '  (select count(*) from public.confirmacoes_acao where acao_id = @acao) as presencas, '
            '  (select count(*) from public.votos where rodada_id = @rodada) as votos, '
            '  (select count(*) from public.acoes where id = @acao) as acoes, '
            '  (select count(*) from public.participacoes_grupo where grupo_id = @grupo) as participacoes, '
            '  (select count(*) from public.grupos where id = @grupo) as grupos',
          ),
          parameters: {
            'acao': candidateId,
            'rodada': roundId,
            'grupo': groupId,
          },
        );
        return rows.single.toColumnMap().map((k, v) => MapEntry(k, v as int));
      }

      final path = 'acao/$candidateId/intacta-capa.jpg';
      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named(
            'insert into public.fotos_capa (acao_id, caminho, enviada_por) '
            'values (@acao, @caminho, @dono)',
          ),
          parameters: {'acao': candidateId, 'caminho': path, 'dono': _uidOwner},
        );
      });

      final before = await snapshot();
      // 2 presenças, não 1: criar a Ação já confirma o criador. O número exato
      // não é desta feature — o que importa é ele não mudar. Ainda assim fica
      // afirmado como não-zero, senão a comparação abaixo passaria comparando
      // nada com nada.
      expect(before['presencas'], greaterThan(0));
      expect(before['votos'], 1);

      await asUser(_uidOwner, () async {
        await conn.execute(
          Sql.named('delete from public.fotos_capa where caminho = @c'),
          parameters: {'c': path},
        );
      });

      expect(await snapshot(), before,
          reason: 'remover a capa não pode mexer em presença, voto, Ação, '
              'participação nem Grupo');
      expect(await isQueued(path), isTrue);

      await conn.execute(
        Sql.named('delete from public.votos where rodada_id = @r'),
        parameters: {'r': roundId},
      );
      await conn.execute(
        Sql.named('delete from public.confirmacoes_acao where acao_id = @a'),
        parameters: {'a': candidateId},
      );
    },
  );

  test(
    '(h) FR-021/SC-005: apagar o Grupo leva a capa e enfileira o arquivo',
    () async {
      // Não existe tela que apague Grupo — o plano registra isso no achado 1.
      // É exatamente por isso que este teste importa: no dia em que ela
      // existir, ninguém vai lembrar de conferir a capa. O cascade e o gatilho
      // já cobrem, e aqui isso vira afirmação verificável em vez de intenção.
      final ownGroupRows = await conn.execute(
        Sql.named(
          "insert into public.grupos (nome, categoria, horario, local, dono_id) "
          "values ('Grupo a Apagar Orfao', 'Ministério Jovem', 's', 'Sede', @dono) returning id",
        ),
        parameters: {'dono': _uidOwner},
      );
      final doomedGroupId = ownGroupRows.single.toColumnMap()['id']!;

      final path = 'grupo/$doomedGroupId/apagado-orfao.jpg';
      await conn.execute(
        Sql.named(
          'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
          'values (@g, @c, @d)',
        ),
        parameters: {'g': doomedGroupId, 'c': path, 'd': _uidOwner},
      );
      expect(await coverCountFor('grupo_id', doomedGroupId), 1);

      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': doomedGroupId},
      );

      expect(await coverCountFor('grupo_id', doomedGroupId), 0);
      expect(await isQueued(path), isTrue,
          reason: 'o cascade tem de disparar o gatilho, senão o arquivo fica '
              'no bucket sem nenhuma linha que o referencie');

      await conn.execute(
        Sql.named('delete from public.capas_a_remover where caminho = @c'),
        parameters: {'c': path},
      );
    },
  );
}

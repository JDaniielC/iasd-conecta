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
}

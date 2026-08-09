import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000038';
const _uidProponente = '70000000-0000-0000-0000-000000000039';
const _uidOutroParticipante = '70000000-0000-0000-0000-000000000040';

void main() {
  late Connection conn;
  late Object groupId;
  late Object acaoConfirmadaId;

  Future<void> comoUsuario(String uid, Future<void> Function() action) async {
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

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, name: 'Dono CancelarAcaoGrupo');
    await criarPerfilDeTeste(conn, _uidProponente, name: 'Proponente CancelarAcaoGrupo');
    await criarPerfilDeTeste(conn, _uidOutroParticipante, name: 'Outro CancelarAcaoGrupo');

    final grupoRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo CancelarAcaoGrupo', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    groupId = grupoRows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @a), (@grupo, @b)',
      ),
      parameters: {'grupo': groupId, 'a': _uidProponente, 'b': _uidOutroParticipante},
    );

    late Object actionId;
    late Object votingRoundId;
    await comoUsuario(_uidProponente, () async {
      final rodadaRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @proponente, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': groupId, 'proponente': _uidProponente},
      );
      votingRoundId = rodadaRows.single.toColumnMap()['id']!;

      final candRows = await conn.execute(
        Sql.named(
          "insert into public.acoes (nome, data_hora, local, criador_id, rodada_id) "
          "values ('Única Candidata Cancelar', now() + interval '5 days', 'Sede', @proponente, @rodada) "
          "returning id",
        ),
        parameters: {'proponente': _uidProponente, 'rodada': votingRoundId},
      );
      actionId = candRows.single.toColumnMap()['id']!;
    });

    // fecha a rodada forçado pelo dono — a única candidata vira Ação de Grupo confirmada
    await comoUsuario(_uidDono, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    acaoConfirmadaId = actionId;
  });

  tearDownAll(() async {
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
    await limparUsuarioDeTeste(conn, _uidDono);
    await limparUsuarioDeTeste(conn, _uidProponente);
    await limparUsuarioDeTeste(conn, _uidOutroParticipante);
    await conn.close();
  });

  test('participante que não é Dono nem propôs não consegue cancelar', () async {
    await comoUsuario(_uidOutroParticipante, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': acaoConfirmadaId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': acaoConfirmadaId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNull);
  });

  test('FR-016: Dono do Grupo cancela mesmo sem ter proposto a vencedora', () async {
    await comoUsuario(_uidDono, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': acaoConfirmadaId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': acaoConfirmadaId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });
}

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000033';

void main() {
  late Connection conn;
  late Object grupoId;
  late Object votingRoundId;

  Future<void> comoUsuario(String uid, Future<void> Function() acao) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await acao();
    } finally {
      await conn.execute('reset role');
    }
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono ApuracaoSemCandidata');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo ApuracaoSemCandidata', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = rows.single.toColumnMap()['id']!;

    late Object rodada;
    await comoUsuario(_uidDono, () async {
      final rodadaRows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodada = rodadaRows.single.toColumnMap()['id']!;
    });
    votingRoundId = rodada;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    await limparUsuarioDeTeste(conn, _uidDono);
    await conn.close();
  });

  test('FR-018: Rodada sem candidata fecha sem vencedora', () async {
    await comoUsuario(_uidDono, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@rodada, true)'),
        parameters: {'rodada': votingRoundId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select fechada_em, vencedora_id from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': votingRoundId},
    );
    final row = rows.single.toColumnMap();
    expect(row['fechada_em'], isNotNull);
    expect(row['vencedora_id'], isNull);
  });
}

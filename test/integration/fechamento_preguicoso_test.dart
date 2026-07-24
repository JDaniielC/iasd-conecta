import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000024';

void main() {
  late Connection conn;
  late Object grupoId;

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
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono FechamentoPreguicoso');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo FechamentoPreguicoso', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = rows.single.toColumnMap()['id']!;
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

  test('FR-008: não fecha antes do prazo mesmo sem forçar', () async {
    late Object rodadaId;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() + interval '1 day') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodadaId = rows.single.toColumnMap()['id']!;
    });

    await conn.execute(
      Sql.named('select public.fechar_rodada_se_devido(@rodada)'),
      parameters: {'rodada': rodadaId},
    );

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': rodadaId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNull);
  });

  test('FR-008: fecha (e apura sem candidata) quando o prazo já passou', () async {
    late Object rodadaId;
    await comoUsuario(_uidDono, () async {
      final rows = await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @dono, now() - interval '1 hour') returning id",
        ),
        parameters: {'grupo': grupoId, 'dono': _uidDono},
      );
      rodadaId = rows.single.toColumnMap()['id']!;
    });

    await conn.execute(
      Sql.named('select public.fechar_rodada_se_devido(@rodada)'),
      parameters: {'rodada': rodadaId},
    );

    final rows = await conn.execute(
      Sql.named('select fechada_em from public.rodadas_votacao where id = @rodada'),
      parameters: {'rodada': rodadaId},
    );
    expect(rows.single.toColumnMap()['fechada_em'], isNotNull);
  });
}

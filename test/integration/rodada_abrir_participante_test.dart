import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidDono = '70000000-0000-0000-0000-000000000010';
const _uidParticipante = '70000000-0000-0000-0000-000000000011';
const _uidForaDoGrupo = '70000000-0000-0000-0000-000000000012';

void main() {
  late Connection conn;
  late Object grupoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidDono, nome: 'Dono AbrirRodada');
    await criarPerfilDeTeste(conn, _uidParticipante, nome: 'Participante AbrirRodada');
    await criarPerfilDeTeste(conn, _uidForaDoGrupo, nome: 'ForaDoGrupo AbrirRodada');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo AbrirRodada', 'Ministério Jovem', 'sábados', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidDono},
    );
    grupoId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.participacoes_grupo (grupo_id, usuario_id) values (@grupo, @usuario)',
      ),
      parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
    );
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
    await limparUsuarioDeTeste(conn, _uidParticipante);
    await limparUsuarioDeTeste(conn, _uidForaDoGrupo);
    await conn.close();
  });

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

  test('FR-004: quem não participa do Grupo não abre Rodada', () async {
    await expectLater(
      comoUsuario(_uidForaDoGrupo, () async {
        await conn.execute(
          Sql.named(
            "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
            "values (@grupo, @usuario, now() + interval '1 day')",
          ),
          parameters: {'grupo': grupoId, 'usuario': _uidForaDoGrupo},
        );
      }),
      throwsA(isA<ServerException>()),
    );
  });

  test('participante do Grupo abre Rodada normalmente', () async {
    await comoUsuario(_uidParticipante, () async {
      await conn.execute(
        Sql.named(
          "insert into public.rodadas_votacao (grupo_id, aberta_por, prazo) "
          "values (@grupo, @usuario, now() + interval '1 day')",
        ),
        parameters: {'grupo': grupoId, 'usuario': _uidParticipante},
      );
    });

    final rows = await conn.execute(
      Sql.named('select count(*) as total from public.rodadas_votacao where grupo_id = @grupo'),
      parameters: {'grupo': grupoId},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}

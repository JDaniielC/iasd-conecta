import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change acao-direcionada-a-grupo — a Rodada de votação não reintroduz a Ação
/// restrita.
///
/// O design afirma que a Rodada não precisa de regra própria: Ação candidata é
/// linha de `acoes` com `rodada_id` não nulo, logo já cai em
/// `acoes_select_visivel`. Afirmação a VERIFICAR, não a assumir — é literalmente
/// o que a task 4.7 pede, e é o tipo de suposição que a feature 021 puniu.
///
/// O último caso é o mais importante e o menos óbvio, e existe pelo mesmo motivo
/// que o caso `(f)` de votos_visibilidade_test.dart: `fechar_rodada_se_devido`
/// conta os votos como `security definer`, dona `postgres`, e por isso enxerga
/// todos. Se alguém a converter para `security invoker` depois desta change, a
/// apuração passa a contar só o que o chamador enxerga — e uma candidata
/// restrita simplesmente SOME da contagem para quem é de fora, elegendo outra e
/// APAGANDO as perdedoras. Por isso a candidata restrita aqui é montada para
/// VENCER: montada ao contrário, este teste passa verde numa apuração quebrada.

const _uidOwner = 'a7000000-0000-0000-0000-000000000001';
const _uidMember = 'a7000000-0000-0000-0000-000000000002';
const _uidOutsider = 'a7000000-0000-0000-0000-000000000003';

/// O Visitante: pessoa sem cadastro, e por isso SEM linha em `perfis`. Tem
/// sessão — `signInAnonymously` no arranque do app —, então chega ao banco
/// como `authenticated`. Até 2026-08-16 este teste rodava como `anon`, que é a
/// requisição sem credencial nenhuma e não é o que o app produz.
const _uidVisitor = 'a7000000-0000-0000-0000-0000000000f0';

const _allUids = [_uidOwner, _uidMember, _uidOutsider];

void main() {
  late Connection conn;
  late String groupId;
  late String roundId;
  late String restrictedId;

  Future<List<String>> visibleCandidates() async {
    final r = await conn.execute(
      Sql.named('select nome from public.acoes where rodada_id = @r'),
      parameters: {'r': roundId},
    );
    return r.map((row) => row.toColumnMap()['nome'] as String).toList();
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona A7');
    await createTestProfile(conn, _uidMember, name: 'Participante A7');
    await createTestProfile(conn, _uidOutsider, name: 'De Fora A7');
    await createTestVisitor(conn, _uidVisitor);

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo A7');
    await joinGroup(conn, groupId, _uidMember);
    roundId = await createVotingRound(
      conn,
      groupId: groupId,
      openedBy: _uidOwner,
    );

    restrictedId = await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      restricted: true,
      name: 'Candidata restrita A7',
    );
    await createGroupAction(
      conn,
      creatorId: _uidOwner,
      roundId: roundId,
      name: 'Candidata pública A7',
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'update public.rodadas_votacao set vencedora_id = null where grupo_id = @g',
      ),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.rodadas_votacao where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    // FORA de `_allUids` de propósito: em outros arquivos uma lista com esse
    // nome ALIMENTA `createTestProfile`, e Visitante é justamente quem não tem
    // Perfil. Mesmo nome, dois contratos — a limpeza dele vem à parte.
    await cleanUpTestUser(conn, _uidVisitor);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('quem é de fora não vê a candidata restrita na Rodada', () async {
    final vistas = await asUser(conn, _uidOutsider, visibleCandidates);
    expect(vistas, ['Candidata pública A7']);
  });

  test('Visitante não vê a candidata restrita na Rodada', () async {
    final vistas = await asVisitor(conn, _uidVisitor, visibleCandidates);
    expect(vistas, ['Candidata pública A7']);
  });

  test('quem participa vê as duas candidatas', () async {
    final vistas = await asUser(conn, _uidMember, visibleCandidates);
    expect(vistas, hasLength(2));
  });

  test('a apuração enxerga a candidata restrita e ela vence; para quem é de '
      'fora a vencedora não vaza', () async {
    for (final uid in [_uidOwner, _uidMember]) {
      await asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'insert into public.votos (rodada_id, usuario_id, candidata_id) '
            'values (@r, @u, @c)',
          ),
          parameters: {'r': roundId, 'u': uid, 'c': restrictedId},
        );
      });
    }

    await asUser(conn, _uidOwner, () async {
      await conn.execute(
        Sql.named('select public.fechar_rodada_se_devido(@r, true)'),
        parameters: {'r': roundId},
      );
    });

    final vencedora = await conn.execute(
      Sql.named(
        'select vencedora_id from public.rodadas_votacao where id = @r',
      ),
      parameters: {'r': roundId},
    );
    expect(
      vencedora.single.toColumnMap()['vencedora_id'],
      restrictedId,
      reason:
          'se falhou aqui, a apuração deixou de contar a candidata restrita',
    );

    // A Rodada é pública (`rodadas_votacao_select_public`), então o id da
    // vencedora é legível. O que não pode vazar é a Ação: nome, data, local.
    final vazamento = await asUser(conn, _uidOutsider, () async {
      return conn.execute(
        Sql.named(
          'select a.nome, a.data_hora, a.local from public.rodadas_votacao r '
          'join public.acoes a on a.id = r.vencedora_id where r.id = @r',
        ),
        parameters: {'r': roundId},
      );
    });
    expect(vazamento, isEmpty);

    // E para quem participa, a vencedora aparece normalmente.
    final paraDentro = await asUser(conn, _uidMember, () async {
      return conn.execute(
        Sql.named(
          'select a.nome from public.rodadas_votacao r '
          'join public.acoes a on a.id = r.vencedora_id where r.id = @r',
        ),
        parameters: {'r': roundId},
      );
    });
    expect(paraDentro.single.toColumnMap()['nome'], 'Candidata restrita A7');
  });
}

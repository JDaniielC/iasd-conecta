import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'convite_helper.dart';
import 'db_test_helper.dart';

/// Change `convite-para-acao` — o Grupo é o contexto do convite, não enfeite.
///
/// A mesma pessoa em dois Grupos aparece nos dois de propósito: é por esse
/// Grupo que quem recebe vai filtrar, e é ele que a pessoa vê como explicação
/// de origem ("pelo Grupo X"). Achatar em uma linha só obrigaria a escolher um
/// Grupo arbitrário e quebraria o filtro do outro lado.

const _uidQuemConvida = 'c2000000-0000-0000-0000-000000000001';
const _uidNosDois = 'c2000000-0000-0000-0000-000000000002';
const _uidSoJovens = 'c2000000-0000-0000-0000-000000000003';
const _uidArquivado = 'c2000000-0000-0000-0000-000000000004';
const _allUids = [_uidQuemConvida, _uidNosDois, _uidSoJovens, _uidArquivado];

void main() {
  late Connection conn;
  late String jovens, musica, velho;
  late String actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidQuemConvida, name: 'Quem Convida C2');
    await createTestProfile(conn, _uidNosDois, name: 'Nos Dois C2');
    await createTestProfile(conn, _uidSoJovens, name: 'So Jovens C2');
    await createTestProfile(conn, _uidArquivado, name: 'Do Arquivado C2');

    jovens = await createGroup(conn, ownerId: _uidQuemConvida, name: 'Jovens C2');
    musica = await createGroup(conn, ownerId: _uidQuemConvida, name: 'Musica C2');
    velho = await createGroup(conn, ownerId: _uidQuemConvida, name: 'Arquivado C2');

    await joinGroup(conn, jovens, _uidNosDois);
    await joinGroup(conn, musica, _uidNosDois);
    await joinGroup(conn, jovens, _uidSoJovens);
    await joinGroup(conn, velho, _uidArquivado);
    await arquivarGrupoDireto(conn, velho);

    actionId =
        await createLooseAction(conn, creatorId: _uidQuemConvida, name: 'Ação C2');
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.convites_acao where acao_id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where acao_id = @a'),
      parameters: {'a': actionId},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': actionId},
    );
    for (final g in [jovens, musica, velho]) {
      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': g},
      );
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('a lista vem agrupada pelos Grupos de quem convida', () async {
    final linhas = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    final grupos = linhas.map((l) => l['grupo_nome']).toSet();
    expect(grupos, {'Jovens C2', 'Musica C2'});
  });

  test('quem participa dos mesmos dois Grupos aparece nos dois', () async {
    final linhas = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    final deNosDois = linhas.where((l) => l['nome_exibido'] == 'Nos Dois C2');
    expect(deNosDois, hasLength(2));
    expect(
      deNosDois.map((l) => l['grupo_nome']).toSet(),
      {'Jovens C2', 'Musica C2'},
    );
  });

  test('quem convida não aparece na própria lista', () async {
    final linhas = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    expect(
      linhas.map((l) => l['nome_exibido']),
      isNot(contains('Quem Convida C2')),
    );
  });

  test('Grupo arquivado não vira seção, e quem só está nele não aparece',
      () async {
    final linhas = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    expect(linhas.map((l) => l['grupo_nome']), isNot(contains('Arquivado C2')));
    expect(
      linhas.map((l) => l['nome_exibido']),
      isNot(contains('Do Arquivado C2')),
    );
  });

  test('ja_confirmou acompanha quem já respondeu ao convite', () async {
    // Segunda metade de "quem convidou acompanha os próprios convites": sem
    // isto a tela diria "já convidado" para sempre, e quem convidou não saberia
    // se ainda precisa chamar mais gente.
    final antes = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    expect(
      antes
          .firstWhere((l) => l['nome_exibido'] == 'So Jovens C2')['ja_confirmou'],
      isFalse,
    );

    await asUser(conn, _uidSoJovens, () async {
      await conn.execute(
        Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@a, @u)'),
        parameters: {'a': actionId, 'u': _uidSoJovens},
      );
    });

    final depois = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    expect(
      depois
          .firstWhere((l) => l['nome_exibido'] == 'So Jovens C2')['ja_confirmou'],
      isTrue,
    );
  });

  test('ja_convidado acompanha o Grupo, não só a pessoa', () async {
    await asUser(
      conn,
      _uidQuemConvida,
      () => convidarParaAcao(conn,
          actionId: actionId, groupId: jovens, invitees: [_uidNosDois]),
    );
    final linhas = await asUser(
        conn, _uidQuemConvida, () => contatosParaConvite(conn, actionId));
    final deNosDois = {
      for (final l in linhas)
        if (l['nome_exibido'] == 'Nos Dois C2')
          l['grupo_nome'] as String: l['ja_convidado'] as bool
    };
    // Convidada por Jovens, ainda convidável por Música — é o mesmo motivo de
    // o Grupo estar na chave primária.
    expect(deNosDois['Jovens C2'], isTrue);
    expect(deNosDois['Musica C2'], isFalse);
  });
}

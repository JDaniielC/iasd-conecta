import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `afirmar-sem-conferir` — as OITO escritas do cliente em que zero
/// linhas significa **recusa**, e nada mais.
///
/// A asserção é `affectedRows`, nunca `expect(..., throwsA(...))`: no Postgres
/// uma policy que recusa não levanta exceção, ela faz a linha não existir para
/// aquela sessão. Um teste que esperasse exceção passaria pelo motivo errado ou
/// não passaria nunca — `CLAUDE.md`, "Recusa de RLS é ausência, não erro".
///
/// Cada caso roda sob o papel `authenticated`, que é o que o app tem. Rodar
/// como `postgres` provaria nada: ele é dono das tabelas e ignora RLS.
///
/// **Nenhum Administrador do distrito é criado aqui, de propósito.** Todos os
/// oito casos são a recusa de quem NÃO tem privilégio, então o privilégio não
/// precisa existir. E `administradores_distrito` é estado global:
/// `excluir_minha_conta` transfere Grupo para o Administrador mais antigo, e um
/// Administrador vivo neste arquivo viraria herdeiro dos Grupos de
/// `account_deletion_test` — medido em 2026-08-20, quatro casos derrubados.

const _uidOwner = 'e7a10000-0000-0000-0000-000000000001';
const _uidStranger = 'e7a10000-0000-0000-0000-000000000002';
const _uidMember = 'e7a10000-0000-0000-0000-000000000003';
/// Tem `auth.users` mas NÃO tem linha em `perfis` — é o único jeito de
/// `updateMyProfile` afetar zero linhas, já que a policy permite escrever na
/// própria linha.
const _uidNoProfile = 'e7a10000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidStranger, _uidMember, _uidNoProfile];

const _groupId = 'e7a10000-0000-0000-0000-0000000000a1';
const _actionId = 'e7a10000-0000-0000-0000-0000000000a2';
const _photoId = 'e7a10000-0000-0000-0000-0000000000a3';
const _churchId = 'e7a10000-0000-0000-0000-0000000000a4';

void main() {
  late Connection conn;

  Future<int> affectedAs(String uid, String sql, Map<String, Object?> params) =>
      asUser(conn, uid, () async {
        final r = await conn.execute(Sql.named(sql), parameters: params);
        return r.affectedRows;
      });

  Future<int> countWhere(String sql, Map<String, Object?> params) async {
    final r = await conn.execute(Sql.named(sql), parameters: params);
    return r.first[0]! as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona do Espaco');
    await createTestProfile(conn, _uidStranger, name: 'Estranha');
    await createTestProfile(conn, _uidMember, name: 'Participante');
    await createTestUser(conn, _uidNoProfile);

    await conn.execute(
      Sql.named('insert into public.grupos (id, nome, categoria, dono_id) '
          "values (@g, 'Grupo da Recusa', 'Ministério Jovem', @o)"),
      parameters: {'g': _groupId, 'o': _uidOwner},
    );
    await conn.execute(
      Sql.named('insert into public.participacoes_grupo (grupo_id, usuario_id) '
          'values (@g, @u) on conflict do nothing'),
      parameters: {'g': _groupId, 'u': _uidMember},
    );
    await conn.execute(
      Sql.named('insert into public.acoes (id, nome, data_hora, local, criador_id) '
          "values (@a, 'Ação da Recusa', now() + interval '7 days', 'Praça', @o)"),
      parameters: {'a': _actionId, 'o': _uidOwner},
    );
    await conn.execute(
      Sql.named('insert into public.fotos_capa (id, grupo_id, caminho, enviada_por) '
          "values (@f, @g, 'grupo/capa.jpg', @o)"),
      parameters: {'f': _photoId, 'g': _groupId, 'o': _uidOwner},
    );
    await conn.execute(
      Sql.named("insert into public.igrejas (id, nome) values (@i, 'Igreja da Recusa')"),
      parameters: {'i': _churchId},
    );
  });

  tearDownAll(() async {
    for (final (sql, params) in <(String, Map<String, Object?>)>[
      ('delete from public.fotos_capa where id = @f', {'f': _photoId}),
      ('delete from public.acoes where id = @a', {'a': _actionId}),
      // O Grupo sai ANTES das participações: apagar `participacoes_grupo` com
      // o Grupo ainda de pé dispara
      // `participacoes_grupo_dono_nao_sai_sem_transferir`, que levanta
      // "transfira a posse do grupo antes de sair" sobre a linha do próprio
      // Dono — criada pelo gatilho `grupos_dono_vira_participante`.
      ('delete from public.grupos where id = @g', {'g': _groupId}),
      ('delete from public.participacoes_grupo where grupo_id = @g', {'g': _groupId}),
      ('delete from public.igrejas where id = @i', {'i': _churchId}),
    ]) {
      await conn.execute(Sql.named(sql), parameters: params);
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('cancelAction: quem não criou a Ação afeta zero linhas', () async {
    final affected = await affectedAs(
      _uidStranger,
      'update public.acoes set cancelada_em = now() where id = @a',
      {'a': _actionId},
    );

    expect(affected, 0);
    expect(
      await countWhere(
        'select count(*) from public.acoes where id = @a and cancelada_em is null',
        {'a': _actionId},
      ),
      1,
      reason: 'a Ação continua ativa para todo mundo',
    );
  });

  test('CoverPhotoRepository.remove: quem não administra o espaço afeta zero',
      () async {
    final affected = await affectedAs(
      _uidStranger,
      'delete from public.fotos_capa where id = @f',
      {'f': _photoId},
    );

    expect(affected, 0);
    expect(
      await countWhere('select count(*) from public.fotos_capa where id = @f',
          {'f': _photoId}),
      1,
      reason: 'a capa continua no ar',
    );
  });

  test('resolveByRemovingImage: mesma tabela, mesma recusa para não-Administrador',
      () async {
    // É a mesma escrita de `remove`, por outra porta: a tela de denúncias
    // apaga a linha de `fotos_capa`. Se uma passa e a outra não, é a policy
    // que mudou, não a tela.
    final affected = await affectedAs(
      _uidMember,
      'delete from public.fotos_capa where id = @f',
      {'f': _photoId},
    );

    expect(affected, 0);
  });

  test('archiveChurch: quem não é Administrador afeta zero linhas', () async {
    final affected = await affectedAs(
      _uidStranger,
      'update public.igrejas set arquivada_em = now() where id = @i',
      {'i': _churchId},
    );

    expect(affected, 0);
    expect(
      await countWhere(
        'select count(*) from public.igrejas where id = @i and arquivada_em is null',
        {'i': _churchId},
      ),
      1,
    );
  });

  test('updateGroup: quem não é Dono afeta zero linhas', () async {
    final affected = await affectedAs(
      _uidMember,
      "update public.grupos set nome = 'Nome Roubado' where id = @g",
      {'g': _groupId},
    );

    expect(affected, 0);
    expect(
      await countWhere(
        "select count(*) from public.grupos where id = @g and nome = 'Grupo da Recusa'",
        {'g': _groupId},
      ),
      1,
      reason: 'o nome não mudou',
    );
  });

  test('removeMember: quem não é Dono não tira ninguém do Grupo', () async {
    final affected = await affectedAs(
      _uidStranger,
      'delete from public.participacoes_grupo where grupo_id = @g and usuario_id = @u',
      {'g': _groupId, 'u': _uidMember},
    );

    expect(affected, 0);
    expect(
      await countWhere(
        'select count(*) from public.participacoes_grupo '
        'where grupo_id = @g and usuario_id = @u',
        {'g': _groupId, 'u': _uidMember},
      ),
      1,
      reason: 'quem participava continua participando',
    );
  });

  test('transferOwnership: quem não é Dono não passa a posse para si', () async {
    final affected = await affectedAs(
      _uidMember,
      'update public.grupos set dono_id = @novo where id = @g',
      {'g': _groupId, 'novo': _uidMember},
    );

    expect(affected, 0);
    expect(
      await countWhere(
        'select count(*) from public.grupos where id = @g and dono_id = @o',
        {'g': _groupId, 'o': _uidOwner},
      ),
      1,
      reason: 'a posse continua de quem era',
    );
  });

  test('updateMyProfile: sem linha em perfis, a escrita não alcança nada',
      () async {
    // A policy permite escrever na PRÓPRIA linha, então recusa por privilégio
    // não existe aqui. Zero acontece por outro motivo — a linha não existe — e
    // o efeito para a pessoa é o mesmo: a tela diria "Dados atualizados." sobre
    // nada.
    final affected = await affectedAs(
      _uidNoProfile,
      "update public.perfis set nome = 'Novo Nome' where id = @u",
      {'u': _uidNoProfile},
    );

    expect(affected, 0);
  });
}

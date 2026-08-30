import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `afirmar-sem-conferir` — o outro lado de
/// `escrita_recusada_test.dart`.
///
/// Três escritas do cliente PODEM afetar zero linhas legitimamente, e por isso
/// não conferem a contagem: `leave`, `dismiss` e `markRead`. Nelas o filtro já
/// carrega a condição que a escrita vai mudar, ou a operação remove o próprio
/// vínculo — zero quer dizer "já estava assim".
///
/// Este arquivo prova as duas metades que sustentam essa decisão:
///
///   1. zero acontece mesmo, e é sucesso (`markRead` de linha já lida);
///   2. a recusa que existe em `leave` NÃO se disfarça de zero — o Dono que não
///      transferiu é barrado pelo trigger, e isso chega como **erro
///      levantado**. É o que separa "já não participo" de "não posso sair", e
///      sem isso a decisão de não conferir a contagem seria um chute.

const _uidOwner = 'e7a20000-0000-0000-0000-000000000001';
const _uidMember = 'e7a20000-0000-0000-0000-000000000002';
const _allUids = [_uidOwner, _uidMember];

const _groupId = 'e7a20000-0000-0000-0000-0000000000a1';
const _notificationId = 'e7a20000-0000-0000-0000-0000000000a2';

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dona que nao sai');
    await createTestProfile(conn, _uidMember, name: 'Participante');
    await conn.execute(
      Sql.named('insert into public.grupos (id, nome, categoria, dono_id) '
          "values (@g, 'Grupo do Zero', 'Ministério Jovem', @o)"),
      parameters: {'g': _groupId, 'o': _uidOwner},
    );
    await conn.execute(
      Sql.named('insert into public.participacoes_grupo (grupo_id, usuario_id) '
          'values (@g, @u) on conflict do nothing'),
      parameters: {'g': _groupId, 'u': _uidMember},
    );
    // Já lida: é a linha que faz `markRead` afetar zero.
    await conn.execute(
      Sql.named('insert into public.notificacoes '
          '(id, destinatario_id, tipo, lida_em) '
          "values (@n, @u, 'convite_recebido', now())"),
      parameters: {'n': _notificationId, 'u': _uidMember},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.notificacoes where id = @n'),
      parameters: {'n': _notificationId},
    );
    // O Grupo sai antes das participações — ver a ordem comentada em
    // `escrita_recusada_test.dart`.
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': _groupId},
    );
    await conn.execute(
      Sql.named('delete from public.participacoes_grupo where grupo_id = @g'),
      parameters: {'g': _groupId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('markRead numa notificação já lida: zero linhas, e é sucesso', () async {
    final affected = await asUser(conn, _uidMember, () async {
      final r = await conn.execute(
        Sql.named('update public.notificacoes set lida_em = now() '
            'where id = any(@ids) and lida_em is null'),
        parameters: {'ids': [_notificationId]},
      );
      return r.affectedRows;
    });

    expect(affected, 0, reason: 'o filtro já exigia lida_em nulo');
    // Nada de errado aconteceu: a linha continua lá e continua lida.
    final r = await conn.execute(
      Sql.named('select count(*) from public.notificacoes '
          'where id = @n and lida_em is not null'),
      parameters: {'n': _notificationId},
    );
    expect(r.first[0], 1);
  });

  test('leave de quem já não participa: zero linhas, e é sucesso', () async {
    // Ninguém apagou nada antes; esta pessoa nunca participou deste Grupo.
    final affected = await asUser(conn, _uidOwner, () async {
      final r = await conn.execute(
        Sql.named('delete from public.participacoes_grupo '
            'where grupo_id = @g and usuario_id = @u'),
        parameters: {'g': _groupId, 'u': 'e7a20000-0000-0000-0000-0000000000ff'},
      );
      return r.affectedRows;
    });

    expect(affected, 0);
  });

  test('o Dono que não transferiu é barrado por ERRO LEVANTADO, não por zero',
      () async {
    // É o que dispensa `leave` de conferir a contagem: as duas situações
    // chegam ao cliente por caminhos diferentes.
    Object? raised;
    try {
      await asUser(conn, _uidOwner, () async {
        await conn.execute(
          Sql.named('delete from public.participacoes_grupo '
              'where grupo_id = @g and usuario_id = @u'),
          parameters: {'g': _groupId, 'u': _uidOwner},
        );
      });
    } catch (e) {
      raised = e;
    }

    expect(raised, isNotNull, reason: 'a recusa do Dono é exceção, não ausência');
    expect(
      raised.toString(),
      contains('transfira a posse do grupo antes de sair'),
    );
    // E a participação dele continua de pé.
    final r = await conn.execute(
      Sql.named('select count(*) from public.participacoes_grupo '
          'where grupo_id = @g and usuario_id = @u'),
      parameters: {'g': _groupId, 'u': _uidOwner},
    );
    expect(r.first[0], 1);
  });
}

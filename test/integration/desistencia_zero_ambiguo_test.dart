import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `afirmar-sem-conferir` — `withdraw` é a única das doze escritas em
/// que zero linhas tem DUAS causas, e elas são opostas para quem olha a tela.
///
/// `confirmacoes_acao_delete_self` recusa quando `public.acao_encerrada(
/// acao_id)` — de propósito, para `confirmacoes_acao_promover_fila` não
/// promover alguém depois do encerramento (migration `20260809174740`).
///
/// Este arquivo prova que as duas situações **são indistinguíveis pela
/// contagem**, que é exatamente o que obriga `withdraw` a perguntar o estado
/// antes de decidir a frase:
///
///   nunca confirmou, Ação aberta   → 0 linhas, e está tudo certo
///   confirmada, Ação encerrada     → 0 linhas, e ela CONTINUA constando como
///                                    presente num encontro que já aconteceu

const _uidPresent = 'e7a30000-0000-0000-0000-000000000001';
const _uidAbsent = 'e7a30000-0000-0000-0000-000000000002';
const _allUids = [_uidPresent, _uidAbsent];

const _openActionId = 'e7a30000-0000-0000-0000-0000000000a1';
const _endedActionId = 'e7a30000-0000-0000-0000-0000000000a2';

void main() {
  late Connection conn;

  Future<int> withdrawAs(String uid, String actionId) =>
      asUser(conn, uid, () async {
        final r = await conn.execute(
          Sql.named('delete from public.confirmacoes_acao '
              'where acao_id = @a and usuario_id = @u'),
          parameters: {'a': actionId, 'u': uid},
        );
        return r.affectedRows;
      });

  Future<int> countConfirmations(String actionId, String uid) async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.confirmacoes_acao '
          'where acao_id = @a and usuario_id = @u'),
      parameters: {'a': actionId, 'u': uid},
    );
    return r.first[0]! as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidPresent, name: 'Confirmada');
    await createTestProfile(conn, _uidAbsent, name: 'Nunca confirmou');

    await conn.execute(
      Sql.named('insert into public.acoes (id, nome, data_hora, local, criador_id) '
          "values (@a, 'Ação aberta', now() + interval '7 days', 'Praça', @u)"),
      parameters: {'a': _openActionId, 'u': _uidPresent},
    );
    // Encerrada = passou de data_hora + 4h, o intervalo de `acao_encerrada`.
    await conn.execute(
      Sql.named('insert into public.acoes (id, nome, data_hora, local, criador_id) '
          "values (@a, 'Ação encerrada', now() - interval '2 days', 'Praça', @u)"),
      parameters: {'a': _endedActionId, 'u': _uidPresent},
    );
    // `on conflict do nothing` porque quem cria a Ação já entra confirmada por
    // gatilho. A confirmação entra por baixo da policy de propósito: confirmar
    // numa Ação encerrada também é recusado, e o que interessa aqui é o estado
    // final, não como ele foi alcançado.
    await conn.execute(
      Sql.named('insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@a, @u) on conflict do nothing'),
      parameters: {'a': _endedActionId, 'u': _uidPresent},
    );
  });

  tearDownAll(() async {
    for (final a in [_openActionId, _endedActionId]) {
      await conn.execute(
        Sql.named('delete from public.confirmacoes_acao where acao_id = @a'),
        parameters: {'a': a},
      );
      await conn.execute(
        Sql.named('delete from public.acoes where id = @a'),
        parameters: {'a': a},
      );
    }
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('a Ação encerrada É reconhecida como encerrada pelo banco', () async {
    final r = await conn.execute(
      Sql.named('select public.acao_encerrada(@a::uuid), '
          'public.acao_encerrada(@b::uuid)'),
      parameters: {'a': _endedActionId, 'b': _openActionId},
    );
    expect(r.first[0], isTrue);
    expect(r.first[1], isFalse);
  });

  test('CAUSA 1 — nunca confirmou, Ação aberta: zero linhas, e está tudo certo',
      () async {
    expect(await withdrawAs(_uidAbsent, _openActionId), 0);
  });

  test('CAUSA 2 — confirmada, Ação encerrada: zero linhas, e a presença FICA',
      () async {
    expect(await withdrawAs(_uidPresent, _endedActionId), 0,
        reason: 'a policy recusa por acao_encerrada, sem levantar erro');
    expect(
      await countConfirmations(_endedActionId, _uidPresent),
      1,
      reason: 'ela continua constando como presente num encontro que acabou',
    );
  });

  test('as duas causas são indistinguíveis pela contagem', () async {
    final semConfirmacao = await withdrawAs(_uidAbsent, _openActionId);
    final recusada = await withdrawAs(_uidPresent, _endedActionId);

    expect(semConfirmacao, recusada,
        reason: 'mesmo número, situações opostas — é por isso que `withdraw` '
            'precisa ler o estado antes de escolher a frase');
  });
}

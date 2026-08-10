import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Feature 011, FR-005/FR-006/FR-007.
///
/// A promessa: depois que a Ação encerra, ninguém é promovido da fila de
/// espera. Esconder o botão na tela é promessa; a política de acesso é o que
/// executa. Este arquivo é a prova.
///
/// O caso (c) — exclusão de conta — existe porque o bloqueio tem um jeito
/// óbvio e errado de ser feito: um `trigger before delete` genérico em
/// `confirmacoes_acao` bloquearia também o delete que `excluir_minha_conta`
/// faz, e a pessoa ficaria sem conseguir apagar a conta. Bug de LGPD criado
/// por uma feature de UX.

const _uidOwner = '70000000-0000-0000-0000-000000000080';
const _uidFirst = '70000000-0000-0000-0000-000000000081';
const _uidSecond = '70000000-0000-0000-0000-000000000082';

Future<void> _asUser(
  Connection conn,
  String uid,
  Future<void> Function() action,
) async {
  await conn.execute('set role authenticated');
  await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
  try {
    await action();
  } finally {
    await conn.execute('reset role');
    await conn.execute('reset request.jwt.claims');
  }
}

/// Cria uma Ação com 2 vagas.
///
/// São 2, não 1, porque o trigger `criar_confirmacao_do_criador` já confirma o
/// criador na criação — ele ocupa a primeira vaga. Com 2, o criador e o
/// primeiro convidado ficam confirmados, e o segundo cai na fila, que é o
/// estado que este arquivo precisa.
Future<String> _createActionWithTwoSeats(
  Connection conn, {
  required String creatorId,
  required DateTime dateTime,
}) async {
  final r = await conn.execute(
    Sql.named(
      'insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) '
      "values ('Visita a afastado', @dh, 'alto jose leal', 2, @criador) "
      'returning id',
    ),
    parameters: {'dh': dateTime.toUtc(), 'criador': creatorId},
  );
  return r.first[0] as String;
}

Future<String?> _statusOf(Connection conn, String actionId, String uid) async {
  final r = await conn.execute(
    Sql.named(
      'select status from public.confirmacoes_acao '
      'where acao_id = @a and usuario_id = @u',
    ),
    parameters: {'a': actionId, 'u': uid},
  );
  return r.isEmpty ? null : r.first[0] as String;
}

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in [_uidOwner, _uidFirst, _uidSecond]) {
      await createTestUser(conn, uid);
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }
  });

  tearDownAll(() async {
    // Escopado aos UUIDs deste arquivo. `dart test` roda os arquivos em
    // paralelo, e um `delete from public.acoes` sem filtro apaga o arranjo de
    // quem estiver rodando junto — falha que aparece longe da causa.
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao where usuario_id = any(@u)'),
      parameters: {'u': [_uidOwner, _uidFirst, _uidSecond]},
    );
    await conn.execute(
      Sql.named('delete from public.confirmacoes_acao c using public.acoes a '
          'where c.acao_id = a.id and a.criador_id = any(@u)'),
      parameters: {'u': [_uidOwner, _uidFirst, _uidSecond]},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = any(@u)'),
      parameters: {'u': [_uidOwner, _uidFirst, _uidSecond]},
    );
    for (final uid in [_uidOwner, _uidFirst, _uidSecond]) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    '(a) em Ação encerrada, desistir é recusado e ninguém sobe da fila (FR-007)',
    () async {
      // Ação de 5h atrás: passou de data_hora + 4h, logo está encerrada.
      final actionId = await _createActionWithTwoSeats(
        conn,
        creatorId: _uidOwner,
        dateTime: DateTime.now().subtract(const Duration(hours: 5)),
      );

      // Monta o estado ANTES de encerrar não é possível pelo relógio, então as
      // linhas entram direto: o trigger de status decide confirmado vs fila.
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@a, @u1), (@a, @u2)',
        ),
        parameters: {'a': actionId, 'u1': _uidFirst, 'u2': _uidSecond},
      );
      expect(await _statusOf(conn, actionId, _uidFirst), 'confirmado');
      expect(await _statusOf(conn, actionId, _uidSecond), 'fila');

      // Quem tem a vaga tenta desistir, já encerrada.
      await _asUser(conn, _uidFirst, () async {
        await conn.execute(
          Sql.named(
            'delete from public.confirmacoes_acao '
            'where acao_id = @a and usuario_id = @u',
          ),
          parameters: {'a': actionId, 'u': _uidFirst},
        );
      });

      // A política recusa em silêncio: 0 linhas afetadas, nada muda.
      expect(await _statusOf(conn, actionId, _uidFirst), 'confirmado',
          reason: 'a confirmação não podia ter sido apagada');
      expect(await _statusOf(conn, actionId, _uidSecond), 'fila',
          reason: 'ninguém pode ser promovido depois do encerramento');
    },
  );

  test(
    '(b) em Ação NÃO encerrada, desistir ainda promove o próximo da fila',
    () async {
      final actionId = await _createActionWithTwoSeats(
        conn,
        creatorId: _uidOwner,
        dateTime: DateTime.now().add(const Duration(days: 2)),
      );

      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@a, @u1), (@a, @u2)',
        ),
        parameters: {'a': actionId, 'u1': _uidFirst, 'u2': _uidSecond},
      );
      expect(await _statusOf(conn, actionId, _uidSecond), 'fila');

      await _asUser(conn, _uidFirst, () async {
        await conn.execute(
          Sql.named(
            'delete from public.confirmacoes_acao '
            'where acao_id = @a and usuario_id = @u',
          ),
          parameters: {'a': actionId, 'u': _uidFirst},
        );
      });

      expect(await _statusOf(conn, actionId, _uidFirst), isNull);
      expect(await _statusOf(conn, actionId, _uidSecond), 'confirmado',
          reason: 'a promoção automática da fila não pode ter regredido');
    },
  );

  test(
    '(c) excluir_minha_conta funciona com confirmação em Ação encerrada',
    () async {
      // É este caso que impede o bloqueio de FR-007 de virar bug de LGPD.
      //
      // Ao escrever, descobriu-se que o risco é ainda menor do que o plano
      // supunha, por duas razões independentes:
      //   1. `excluir_minha_conta` é `security definer` e não passa por RLS;
      //   2. ela só apaga confirmação de Ação FUTURA (`a.data_hora > now()`).
      //      Confirmação de Ação passada é mantida de propósito, como
      //      histórico (feature 009).
      // Ou seja, a política de FR-007 nunca chega a atravessar o caminho da
      // exclusão: Ação futura não está encerrada, e Ação encerrada não é
      // tocada. O teste trava as duas metades.
      const uidLeaving = '70000000-0000-0000-0000-000000000083';
      await createTestUser(conn, uidLeaving);
      await createTestProfile(conn, uidLeaving, name: 'Pessoa que sai');

      final ended = await _createActionWithTwoSeats(
        conn,
        creatorId: _uidOwner,
        dateTime: DateTime.now().subtract(const Duration(hours: 5)),
      );
      final upcoming = await _createActionWithTwoSeats(
        conn,
        creatorId: _uidOwner,
        dateTime: DateTime.now().add(const Duration(days: 2)),
      );
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@enc, @u), (@fut, @u)',
        ),
        parameters: {'enc': ended, 'fut': upcoming, 'u': uidLeaving},
      );

      // A exclusão precisa concluir sem erro — é o que o bloqueio poderia ter
      // quebrado.
      await _asUser(conn, uidLeaving, () async {
        await conn.execute('select public.excluir_minha_conta()');
      });

      final profile = await conn.execute(
        Sql.named('select nome, anonimizado_em from public.perfis where id = @u'),
        parameters: {'u': uidLeaving},
      );
      expect(profile.first[0], 'Membro removido',
          reason: 'a anonimização da feature 009 tem de ter acontecido');
      expect(profile.first[1], isNotNull);

      expect(await _statusOf(conn, upcoming, uidLeaving), isNull,
          reason: 'vínculo vivo (Ação futura) sai junto com a conta');
      expect(await _statusOf(conn, ended, uidLeaving), isNotNull,
          reason: 'vínculo histórico (Ação encerrada) fica, por decisão da 009');
    },
  );
}

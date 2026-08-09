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

const _uidDono = '70000000-0000-0000-0000-000000000080';
const _uidPrimeiro = '70000000-0000-0000-0000-000000000081';
const _uidSegundo = '70000000-0000-0000-0000-000000000082';

Future<void> _comoUsuario(
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
Future<String> _criarAcaoComUmaVaga(
  Connection conn, {
  required String criadorId,
  required DateTime dataHora,
}) async {
  final r = await conn.execute(
    Sql.named(
      'insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) '
      "values ('Visita a afastado', @dh, 'alto jose leal', 2, @criador) "
      'returning id',
    ),
    parameters: {'dh': dataHora.toUtc(), 'criador': criadorId},
  );
  return r.first[0] as String;
}

Future<String?> _statusDe(Connection conn, String acaoId, String uid) async {
  final r = await conn.execute(
    Sql.named(
      'select status from public.confirmacoes_acao '
      'where acao_id = @a and usuario_id = @u',
    ),
    parameters: {'a': acaoId, 'u': uid},
  );
  return r.isEmpty ? null : r.first[0] as String;
}

void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in [_uidDono, _uidPrimeiro, _uidSegundo]) {
      await criarUsuarioDeTeste(conn, uid);
      await criarPerfilDeTeste(conn, uid, name: 'Pessoa ${uid.substring(31)}');
    }
  });

  tearDownAll(() async {
    await conn.execute('delete from public.confirmacoes_acao');
    await conn.execute('delete from public.acoes');
    for (final uid in [_uidDono, _uidPrimeiro, _uidSegundo]) {
      await limparUsuarioDeTeste(conn, uid);
    }
    await conn.close();
  });

  test(
    '(a) em Ação encerrada, desistir é recusado e ninguém sobe da fila (FR-007)',
    () async {
      // Ação de 5h atrás: passou de data_hora + 4h, logo está encerrada.
      final acaoId = await _criarAcaoComUmaVaga(
        conn,
        criadorId: _uidDono,
        dataHora: DateTime.now().subtract(const Duration(hours: 5)),
      );

      // Monta o estado ANTES de encerrar não é possível pelo relógio, então as
      // linhas entram direto: o trigger de status decide confirmado vs fila.
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@a, @u1), (@a, @u2)',
        ),
        parameters: {'a': acaoId, 'u1': _uidPrimeiro, 'u2': _uidSegundo},
      );
      expect(await _statusDe(conn, acaoId, _uidPrimeiro), 'confirmado');
      expect(await _statusDe(conn, acaoId, _uidSegundo), 'fila');

      // Quem tem a vaga tenta desistir, já encerrada.
      await _comoUsuario(conn, _uidPrimeiro, () async {
        await conn.execute(
          Sql.named(
            'delete from public.confirmacoes_acao '
            'where acao_id = @a and usuario_id = @u',
          ),
          parameters: {'a': acaoId, 'u': _uidPrimeiro},
        );
      });

      // A política recusa em silêncio: 0 linhas afetadas, nada muda.
      expect(await _statusDe(conn, acaoId, _uidPrimeiro), 'confirmado',
          reason: 'a confirmação não podia ter sido apagada');
      expect(await _statusDe(conn, acaoId, _uidSegundo), 'fila',
          reason: 'ninguém pode ser promovido depois do encerramento');
    },
  );

  test(
    '(b) em Ação NÃO encerrada, desistir ainda promove o próximo da fila',
    () async {
      final acaoId = await _criarAcaoComUmaVaga(
        conn,
        criadorId: _uidDono,
        dataHora: DateTime.now().add(const Duration(days: 2)),
      );

      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@a, @u1), (@a, @u2)',
        ),
        parameters: {'a': acaoId, 'u1': _uidPrimeiro, 'u2': _uidSegundo},
      );
      expect(await _statusDe(conn, acaoId, _uidSegundo), 'fila');

      await _comoUsuario(conn, _uidPrimeiro, () async {
        await conn.execute(
          Sql.named(
            'delete from public.confirmacoes_acao '
            'where acao_id = @a and usuario_id = @u',
          ),
          parameters: {'a': acaoId, 'u': _uidPrimeiro},
        );
      });

      expect(await _statusDe(conn, acaoId, _uidPrimeiro), isNull);
      expect(await _statusDe(conn, acaoId, _uidSegundo), 'confirmado',
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
      const uidQueSai = '70000000-0000-0000-0000-000000000083';
      await criarUsuarioDeTeste(conn, uidQueSai);
      await criarPerfilDeTeste(conn, uidQueSai, name: 'Pessoa que sai');

      final encerrada = await _criarAcaoComUmaVaga(
        conn,
        criadorId: _uidDono,
        dataHora: DateTime.now().subtract(const Duration(hours: 5)),
      );
      final futura = await _criarAcaoComUmaVaga(
        conn,
        criadorId: _uidDono,
        dataHora: DateTime.now().add(const Duration(days: 2)),
      );
      await conn.execute(
        Sql.named(
          'insert into public.confirmacoes_acao (acao_id, usuario_id) '
          'values (@enc, @u), (@fut, @u)',
        ),
        parameters: {'enc': encerrada, 'fut': futura, 'u': uidQueSai},
      );

      // A exclusão precisa concluir sem erro — é o que o bloqueio poderia ter
      // quebrado.
      await _comoUsuario(conn, uidQueSai, () async {
        await conn.execute('select public.excluir_minha_conta()');
      });

      final perfil = await conn.execute(
        Sql.named('select nome, anonimizado_em from public.perfis where id = @u'),
        parameters: {'u': uidQueSai},
      );
      expect(perfil.first[0], 'Membro removido',
          reason: 'a anonimização da feature 009 tem de ter acontecido');
      expect(perfil.first[1], isNotNull);

      expect(await _statusDe(conn, futura, uidQueSai), isNull,
          reason: 'vínculo vivo (Ação futura) sai junto com a conta');
      expect(await _statusDe(conn, encerrada, uidQueSai), isNotNull,
          reason: 'vínculo histórico (Ação encerrada) fica, por decisão da 009');
    },
  );
}

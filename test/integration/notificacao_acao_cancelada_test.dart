import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — o aviso some quando o assunto some.
///
/// Duas formas diferentes de sumir, e elas não são a mesma coisa:
///   - Ação CANCELADA: a linha do aviso continua na tabela, e a VIEW a filtra.
///     É reversível e não perde rastro.
///   - Ação APAGADA: a linha do aviso vai junto, por `on delete cascade`.
///
/// O contador e a lista leem os dois da view, então o que sai da view sai dos
/// dois ao mesmo tempo — que é o requisito de eles baterem.

const _uidDona = 'f7000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;
  late String acaoViva, acaoCancelada, acaoParaApagar;

  Future<String> novaAcao(String nome) =>
      createLooseAction(conn, creatorId: _uidDona, name: nome);

  Future<void> avisoSobre(String? acaoId) async {
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo, acao_id) "
        "values (@d, 'convite_recebido', @a)",
      ),
      parameters: {'d': _uidDona, 'a': acaoId},
    );
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona F7');
    acaoViva = await novaAcao('F7 viva');
    acaoCancelada = await novaAcao('F7 cancelada');
    acaoParaApagar = await novaAcao('F7 apagada');
    for (final a in [acaoViva, acaoCancelada, acaoParaApagar]) {
      await avisoSobre(a);
    }
    await avisoSobre(null); // aviso sem assunto: nunca é filtrado
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, [_uidDona]);
    await conn.execute(
      Sql.named('delete from public.acoes where criador_id = @c'),
      parameters: {'c': _uidDona},
    );
    await cleanUpTestUser(conn, _uidDona);
    await conn.close();
  });

  test('aviso de Ação cancelada sai da view, e a linha continua na tabela',
      () async {
    await conn.execute(
      Sql.named('update public.acoes set cancelada_em = now() where id = @a'),
      parameters: {'a': acaoCancelada},
    );

    final ativos = await asUser(conn, _uidDona, () => notificacoesAtivas(conn));
    expect(ativos.map((n) => n['acao_id']), isNot(contains(acaoCancelada)));
    expect(ativos.map((n) => n['acao_id']), contains(acaoViva));
    expect(ativos.map((n) => n['acao_id']), contains(null),
        reason: 'aviso sem Ação nunca é filtrado');

    final crus = await asUser(conn, _uidDona, () => notificacoesVisiveis(conn));
    expect(crus, hasLength(4), reason: 'a view filtra, não apaga');
  });

  test('aviso de Ação encerrada também sai da view', () async {
    await conn.execute(
      Sql.named("update public.acoes set data_hora = now() - interval '9 hours' where id = @a"),
      parameters: {'a': acaoViva},
    );
    final ativos = await asUser(conn, _uidDona, () => notificacoesAtivas(conn));
    expect(ativos.map((n) => n['acao_id']), isNot(contains(acaoViva)));
  });

  test('Ação apagada leva o aviso junto, por cascata', () async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @a'),
      parameters: {'a': acaoParaApagar},
    );
    final crus = await asUser(conn, _uidDona, () => notificacoesVisiveis(conn));
    expect(crus, hasLength(3), reason: 'a linha do aviso foi junto');
  });
}

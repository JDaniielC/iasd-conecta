import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';
import 'notificacao_helper.dart';

/// Change `notificacoes-in-app` — retenção de 90 dias depois de LIDA.
///
/// Não lido nunca é apagado: se ninguém viu, o prazo não começou. Essa
/// assimetria é o ponto do requisito, e é o que este teste separa.
///
/// O job roda no `pg_cron`, e com o projeto pausado no plano Free o cron para —
/// aviso herdado de `20260810110000_drenagem_capas.sql:14-21`. Aqui isso é
/// ATRASO DE FAXINA, não defeito de correção: nenhum requisito depende de o
/// aviso ter sumido no dia certo. Por isso, diferente da drenagem de capas,
/// esta change não precisa do segundo gatilho no app.

const _uidDona = 'f8000000-0000-0000-0000-000000000001';

void main() {
  late Connection conn;

  Future<void> aviso({required bool lida, required int diasAtras}) async {
    await conn.execute(
      Sql.named(
        "insert into public.notificacoes (destinatario_id, tipo, lida_em, created_at) "
        "values (@d, 'convite_recebido', @l, now() - (@dias || ' days')::interval)",
      ),
      parameters: {
        'd': _uidDona,
        'l': lida ? DateTime.now().toUtc().subtract(Duration(days: diasAtras)) : null,
        'dias': diasAtras.toString(),
      },
    );
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidDona, name: 'Dona F8');
  });

  tearDownAll(() async {
    await limparNotificacoes(conn, [_uidDona]);
    await cleanUpTestUser(conn, _uidDona);
    await conn.close();
  });

  test('lida há mais de 90 dias é apagada; lida recente e não lida antiga ficam',
      () async {
    await aviso(lida: true, diasAtras: 120); // sai
    await aviso(lida: true, diasAtras: 10); // fica
    await aviso(lida: false, diasAtras: 400); // fica — o prazo nunca começou

    final apagadas = await conn.execute(
      'select public.expurgar_notificacoes_lidas() as n',
    );
    expect(apagadas.single.toColumnMap()['n'], 1);

    final r = await conn.execute(
      Sql.named(
          'select lida_em from public.notificacoes where destinatario_id = @d'),
      parameters: {'d': _uidDona},
    );
    expect(r, hasLength(2));
    expect(r.where((x) => x.toColumnMap()['lida_em'] == null), hasLength(1),
        reason: 'a não lida de 400 dias continua lá');
  });

  test('o job está agendado, e é o que executa o prazo', () async {
    final r = await conn.execute(
      "select schedule, command from cron.job where jobname = 'expurgar-notificacoes-lidas'",
    );
    expect(r, hasLength(1));
    expect(r.single.toColumnMap()['command'],
        contains('expurgar_notificacoes_lidas'));
  });
}

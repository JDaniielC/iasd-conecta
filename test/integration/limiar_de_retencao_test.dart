import 'package:iasd_conecta/features/retention/domain/retention_limits.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Change `observador-de-retencao`, tarefa 4.1 — a MESMA costura de
/// `limites_de_chat_test.dart`: `RetentionLimits.staleAfter` é ESCOLHA, não
/// medição (design, "Decisions"), e a escolha só faz sentido comparada contra
/// o agendamento REAL das três faxinas. Sem este teste, um agendamento que
/// virasse semanal deixaria "2 dias sem rodar" soando um alarme falso toda
/// semana, e ninguém no código apontaria a divergência.

final _dailyCron = RegExp(r'^\d{1,2} \d{1,2} \* \* \*$');

void main() {
  late Connection conn;

  setUpAll(() async => conn = await openTestConnection());
  tearDownAll(() => conn.close());

  test('as três faxinas de retenção rodam TODO DIA no pg_cron', () async {
    final r = await conn.execute(
      "select jobname, schedule from cron.job "
      "where jobname in ("
      "  'expurgar-mensagens-de-acao', 'expurgar-mudancas', 'expurgar-rastro'"
      ") order by jobname",
    );

    expect(
      r,
      hasLength(3),
      reason: 'as três faxinas desta change precisam estar agendadas',
    );
    for (final row in r) {
      final m = row.toColumnMap();
      expect(
        m['schedule'],
        matches(_dailyCron),
        reason: '${m['jobname']} não é diário — RetentionLimits.staleAfter '
            'pressupõe que sim',
      );
    }
  });

  test(
    'o limiar de "atrasada" é maior que um dia — a folga que a escolha promete',
    () {
      expect(
        RetentionLimits.staleAfter,
        greaterThan(const Duration(days: 1)),
        reason: 'menos que isso soaria alarme numa execução com só algumas '
            'horas de atraso, e a escolha (design, "Decisions") é '
            'exatamente evitar isso',
      );
    },
  );
}

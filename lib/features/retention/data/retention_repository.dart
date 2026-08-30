import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/retention_run.dart';

/// Único ponto de acesso a `execucoes_de_faxina`.
///
/// A RLS já decide quem vê — braço único do Administrador do distrito
/// (`execucoes_de_faxina_select_admin`, migration `20260830120000`). Este
/// repositório não checa permissão nenhuma, pelo mesmo desenho de
/// `ChatRepository`.
class RetentionRepository {
  RetentionRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'execucoes_de_faxina';

  /// A execução mais recente de CADA faxina, mais recente primeiro.
  ///
  /// Uma faxina sem nenhuma linha simplesmente não aparece na lista — é o
  /// caso "nunca rodou", e quem decide o que fazer com isso é a TELA
  /// (comparando contra [RetentionJob.values]), não este método: aqui não há
  /// como devolver "ausência" para algo que a consulta não sabe que deveria
  /// existir.
  Future<List<RetentionRun>> fetchLatestRuns() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('quando', ascending: false);

    final seen = <String>{};
    final latest = <RetentionRun>[];
    for (final row in rows) {
      final run = RetentionRun.fromMap(row);
      if (seen.add(run.job)) latest.add(run);
    }
    return latest;
  }
}

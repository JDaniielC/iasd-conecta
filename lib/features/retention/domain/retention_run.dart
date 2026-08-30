/// Quem disparou a execução — o cron do banco ou o app.
///
/// **É o ponto da change `observador-de-retencao`.** Sem esta distinção, o
/// segundo gatilho do app escreveria uma linha idêntica à do cron, e a
/// ausência do cron ficaria invisível atrás dela — exatamente o defeito que
/// motivou o rastro existir.
enum RetentionTrigger {
  cron('cron'),
  app('app');

  const RetentionTrigger(this.dbValue);

  /// Valor gravado em `execucoes_de_faxina.disparada_por`.
  final String dbValue;

  static RetentionTrigger fromDb(String value) =>
      RetentionTrigger.values.firstWhere((t) => t.dbValue == value);
}

/// As faxinas de retenção que este build conhece — os valores gravados em
/// `execucoes_de_faxina.faxina`, que são o nome da função que a executa.
///
/// **Lista fechada aqui, aberta no banco.** A coluna é `text` de propósito
/// (`observador-de-retencao`, design "Decisions"): uma faxina nova não exige
/// `alter type`. Este build só sabe desenhar as que existem quando ele foi
/// compilado — uma faxina desconhecida (ex.: `denuncia-como-registro`, que já
/// está prevista) some da tela até o próximo build saber o nome dela, pelo
/// mesmo raciocínio de [ChangeLogType.fromKey] em `change_log_entry.dart`:
/// incompleta por um instante é melhor que a tela quebrar.
enum RetentionJob {
  actionMessages('expurgar_mensagens_de_acao', 'Mensagens de Ação vencidas'),
  changeLog('expurgar_mudancas', 'Histórico de Mudanças recentes'),
  trail('expurgar_rastro', 'Este próprio rastro de execuções');

  const RetentionJob(this.dbValue, this.label);

  /// Valor gravado em `execucoes_de_faxina.faxina`.
  final String dbValue;

  /// O que a tela do Administrador mostra.
  final String label;

  static RetentionJob? fromDb(String value) {
    for (final job in RetentionJob.values) {
      if (job.dbValue == value) return job;
    }
    return null;
  }
}

/// Uma linha de `public.execucoes_de_faxina`.
///
/// **Nenhum dado pessoal**: quando, quanto e qual faxina, nunca quem foi
/// afetado. O que a tela do Administrador julga é [isStale], não o [ranAt]
/// cru — ver `RetentionLimits.staleAfter`.
class RetentionRun {
  const RetentionRun({
    required this.job,
    required this.ranAt,
    required this.deletedCount,
    required this.triggeredBy,
  });

  factory RetentionRun.fromMap(Map<String, dynamic> map) => RetentionRun(
    job: map['faxina'] as String,
    ranAt: DateTime.parse(map['quando'] as String),
    deletedCount: map['quantas'] as int,
    triggeredBy: RetentionTrigger.fromDb(map['disparada_por'] as String),
  );

  /// O valor cru de `faxina` — sempre presente, mesmo quando [RetentionJob.fromDb]
  /// não reconhece (faxina nova que este build ainda não sabe desenhar).
  final String job;

  final DateTime ranAt;
  final int deletedCount;
  final RetentionTrigger triggeredBy;
}

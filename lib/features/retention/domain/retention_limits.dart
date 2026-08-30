/// O limiar de "atrasada", do lado do cliente.
///
/// **ESCOLHA, NÃO MEDIÇÃO** (design de `observador-de-retencao`, "Decisions").
/// As três faxinas rodam diariamente no `pg_cron` — ver os três `cron.job` na
/// migration `20260830120000_observador_de_retencao.sql`. Dois dias e não um:
/// uma execução que atrasa algumas horas é normal (o mesmo raciocínio do
/// segundo gatilho do chat — "algumas horas além da marca exata" — e do
/// `pg_cron` que para com o projeto pausado no plano Free), e um alerta que
/// dispara toda semana deixa de ser lido.
///
/// `test/integration/observador_de_retencao_test.dart` confere que as três
/// faxinas estão de fato agendadas para rodar TODO DIA — se um agendamento
/// virar semanal, este limiar deixa de fazer sentido e precisa mudar junto.
abstract final class RetentionLimits {
  static const staleAfter = Duration(days: 2);
}

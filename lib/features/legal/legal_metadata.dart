/// Versão e data de vigência dos textos legais (Política de Privacidade e
/// Termos de Uso).
///
/// Consentimento colhido sob uma versão não cobre finalidade que uma versão
/// posterior venha a adicionar — por isso a versão fica num só lugar,
/// visível nas duas páginas. `public.perfis.consentimento_lgpd_aceito_em`
/// (ver `supabase/migrations/20260723191202_perfis_igrejas.sql:36`) hoje
/// grava só a data/hora do aceite, sem gravar a versão aceita: se o texto
/// mudar, não há como saber quem aceitou qual versão (ver REVISAO-JURIDICA.md).
abstract final class LegalMetadata {
  static const version = '1.0';
  static const effectiveDate = '24 de julho de 2026';

  /// Controlador dos dados (LGPD). Confirmado pelo fundador em 24/07/2026.
  static const controllerName = 'JOSE DANIEL DESENVOLVIMENTO DE SOFTWARE LTDA';

  /// Canal único para exercício de direitos do titular e contato do
  /// encarregado/DPO (LGPD art. 41) — o próprio fundador, enquanto o app for
  /// pequeno o suficiente para não exigir um encarregado dedicado.
  static const contactEmail = 'jdaniielc@gmail.com';

  /// Região de hospedagem do Supabase em produção — escolhida para manter
  /// o dado em território brasileiro e evitar declarar transferência
  /// internacional (ver REVISAO-JURIDICA.md, item 4). Ainda não provisionada
  /// (ver achado A-3 em `.achados/20260724-direito-digital-iasd.md`) — a
  /// infra que criar o projeto Supabase de produção DEVE usar esta região.
  static const hostingRegion = 'sa-east-1 (São Paulo, Brasil)';
}

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
}

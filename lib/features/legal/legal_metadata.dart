/// Versão e data de vigência dos textos legais (Política de Privacidade e
/// Termos de Uso).
///
/// Consentimento colhido sob uma versão não cobre finalidade que uma versão
/// posterior venha a adicionar — por isso a versão fica num só lugar, visível
/// nas duas páginas.
///
/// Desde a feature 017, o banco registra qual texto cada pessoa aceitou:
/// `public.perfis.consentimento_lgpd_versao` e
/// `consentimento_lgpd_igreja_versao` são carimbadas pelo gatilho
/// `perfis_carimbar_consentimento`, a partir de
/// `public.versao_texto_legal_vigente()`. O cliente diz SE aceitou; o banco diz
/// QUANDO e SOB QUAL TEXTO.
///
/// **[version] é a gêmea de exibição da linha correspondente em
/// `public.versoes_texto_legal`.** Não dá para derivar uma da outra: o texto
/// legal está compilado no binário, e a versão é metadado dele. Publicar texto
/// novo muda as duas **no mesmo commit** — semear a linha na migration e mudar
/// a constante aqui. `test/integration/versao_texto_legal_registro_test.dart`
/// falha se divergirem, porque a divergência não daria erro: gravaria em cada
/// cadastro novo uma versão diferente da que a pessoa leu na tela.
///
/// Aceites anteriores à feature 017 ficam com versão nula, de propósito —
/// `null` quer dizer *desconhecida*, e preenchê-la seria um palpite
/// apresentado como fato. Ver MAPA-DE-DADOS.md, seção Consentimento.
abstract final class LegalMetadata {
  /// 1.2 (feature 021): o voto deixou de ser público.
  ///
  /// 1.3 (feature 015): a seção de crianças passou a descrever a autorização
  /// do responsável, que antes não existia. Sobe porque o texto exibido mudou
  /// de verdade — e desta vez a mudança ADICIONA um tratamento (nome e contato
  /// de um terceiro), então quem se cadastrar a partir de agora aceita algo
  /// diferente de quem se cadastrou antes. É exatamente a distinção que a
  /// feature 017 passou a registrar.
  static const version = '1.3';
  static const effectiveDate = '10 de agosto de 2026';

  /// Controlador dos dados (LGPD). Confirmado pelo fundador em 24/07/2026.
  static const controllerName = 'JOSE DANIEL DESENVOLVIMENTO DE SOFTWARE LTDA';

  /// Canal único para exercício de direitos do titular e contato do
  /// encarregado/DPO (LGPD art. 41) — o próprio fundador, enquanto o app for
  /// pequeno o suficiente para não exigir um encarregado dedicado.
  static const contactEmail = 'jdaniielc@gmail.com';

  /// Região de hospedagem do Supabase em produção — escolhida para manter o
  /// dado em território brasileiro e evitar declarar transferência
  /// internacional (ver REVISAO-JURIDICA.md, item 4).
  ///
  /// **Verificada em 10/08/2026**: o projeto de produção roda mesmo em
  /// `South America (São Paulo)`. Evidência (saída literal do fornecedor, com
  /// data e quem leu) em `INFRA-PRODUCAO.md` § 2 — é de lá que a Política tira
  /// o direito de afirmar que o dado não sai do Brasil.
  ///
  /// A verificação vale para este projeto, não se herda: qualquer ambiente novo
  /// DEVE escolher esta região explicitamente na criação, porque ela não é o
  /// default do fornecedor e não é documentada como alterável depois. A
  /// exigência está em `INFRA-PRODUCAO.md` § 1.
  static const hostingRegion = 'sa-east-1 (São Paulo, Brasil)';
}

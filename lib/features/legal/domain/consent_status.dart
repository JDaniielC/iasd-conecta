import '../legal_metadata.dart';

/// O que a pessoa aceitou, comparado com o que está vigente.
///
/// Existe porque nada no app fazia essa comparação: `consentimento_lgpd_versao`
/// era carimbada na criação do Perfil e nunca mais olhada (`PENDENCIAS.md`
/// 2.29). LGPD art. 8º, §6º pede aviso "com destaque de forma específica do
/// teor das alterações" quando muda a forma ou a duração do tratamento —
/// destaque é o aviso, teor é [changesSinceAccepted].
class ConsentStatus {
  const ConsentStatus({
    required this.acceptedVersion,
    required this.currentVersion,
    required this.changesSinceAccepted,
  });

  /// Versão do texto que a pessoa aceitou.
  ///
  /// `null` significa **desconhecida**, e mais nada. São os aceites colhidos
  /// entre 2026-07-23 e 2026-08-09, quando o app só gravava a data. Atribuir
  /// uma versão a eles pela data seria estimativa apresentada como registro.
  final String? acceptedVersion;

  /// Versão vigente, sempre lida do banco (`versao_texto_legal_vigente()`).
  ///
  /// Nunca de [LegalMetadata]: a constante do binário é o que a tela EXIBE, e
  /// o banco é quem CARIMBA. Comparar a constante consigo mesma nunca acusaria
  /// uma divergência entre as duas.
  final String currentVersion;

  /// O teor das alterações, uma linha por versão publicada depois da aceita.
  ///
  /// Vazia quando não há o que dizer — inclusive no caso de versão
  /// desconhecida, em que a tela precisa admitir que não sabe de onde partir.
  final List<String> changesSinceAccepted;

  bool get isOutdated => acceptedVersion != currentVersion;

  bool get isUnknownVersion => acceptedVersion == null;

  /// Monta o estado a partir das duas pontas, resolvendo o teor pelo catálogo
  /// de [LegalMetadata].
  factory ConsentStatus.resolve({
    required String? acceptedVersion,
    required String currentVersion,
  }) {
    return ConsentStatus(
      acceptedVersion: acceptedVersion,
      currentVersion: currentVersion,
      changesSinceAccepted: LegalMetadata.changesBetween(
        acceptedVersion,
        currentVersion,
      ),
    );
  }
}

/// Contagem de consentimentos por versão do texto legal (feature 017).
///
/// Devolve quantidade, nunca identidade — a pergunta da US2 é "quantas pessoas
/// estão sob cada versão", e responder com nome seria coletar exposição que
/// ninguém pediu (Princípio II).
enum ConsentKind {
  /// Consentimento LGPD dado no cadastro.
  lgpd('lgpd'),

  /// Consentimento destacado de Igreja de origem (LGPD art. 11, I).
  church('igreja');

  const ConsentKind(this.dbValue);

  /// Valor em português porque é o contrato com o banco — a função
  /// `consentimentos_por_versao()` devolve `'lgpd'` e `'igreja'`.
  final String dbValue;

  static ConsentKind fromDbValue(String value) {
    return ConsentKind.values.firstWhere((kind) => kind.dbValue == value);
  }
}

class ConsentTally {
  const ConsentTally({
    required this.kind,
    required this.consentedVersion,
    required this.count,
  });

  final ConsentKind kind;

  /// Versão do texto aceito. **Anulável de propósito**: `null` quer dizer
  /// *desconhecida* — aceite colhido antes da feature 017, quando o banco não
  /// gravava a versão. Nunca é preenchida com palpite (FR-007).
  final String? consentedVersion;

  final int count;

  bool get isVersionUnknown => consentedVersion == null;

  factory ConsentTally.fromMap(Map<String, dynamic> map) {
    return ConsentTally(
      kind: ConsentKind.fromDbValue(map['tipo'] as String),
      consentedVersion: map['versao'] as String?,
      count: (map['quantidade'] as num).toInt(),
    );
  }
}

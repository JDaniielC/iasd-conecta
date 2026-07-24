/// Igreja do distrito — nome mantido pelo Administrador do distrito
/// (feature 005). Renomeado de `Igreja` pra inglês: primeira tradução sob
/// a fronteira de idioma da constituição v1.1.0 (banco continua `igrejas`
/// em português).
class Church {
  const Church({required this.id, required this.name, this.archivedAt});

  final String id;
  final String name;

  /// Não-nulo quando arquivada pelo Administrador do distrito (feature
  /// 005) — some da lista de opções, mas a linha nunca é apagada.
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  factory Church.fromMap(Map<String, dynamic> map) {
    return Church(
      id: map['id'] as String,
      name: map['nome'] as String,
      archivedAt:
          map['arquivada_em'] == null ? null : DateTime.parse(map['arquivada_em'] as String),
    );
  }
}

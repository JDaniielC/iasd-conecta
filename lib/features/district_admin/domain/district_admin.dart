/// Administrador do distrito — papel de alto privilégio atribuído a um
/// Usuário com Conta, concedido só por promoção de outro Administrador já
/// existente (feature 005). Primeiro modelo Dart escrito já em inglês
/// (constituição v1.1.0); a tabela no banco (`administradores_distrito`)
/// permanece em português.
class DistrictAdmin {
  const DistrictAdmin({
    required this.userId,
    required this.promotedBy,
    required this.createdAt,
  });

  final String userId;
  final String promotedBy;
  final DateTime createdAt;

  factory DistrictAdmin.fromMap(Map<String, dynamic> map) {
    return DistrictAdmin(
      userId: map['usuario_id'] as String,
      promotedBy: map['promovido_por'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

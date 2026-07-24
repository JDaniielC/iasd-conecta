enum LeadershipStatus { pending, confirmed, rejected }

/// A self-declaration of Líder/Diretor de Ministério for one Grupo, for one
/// year. Table `liderancas` (Portuguese, unchanged) never has a status
/// column — status is always derived from the two nullable timestamps.
class LeadershipDeclaration {
  const LeadershipDeclaration({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.year,
    required this.declaredAt,
    this.confirmedBy,
    this.confirmedAt,
    this.rejectedAt,
  });

  final String id;
  final String groupId;
  final String userId;
  final int year;
  final DateTime declaredAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;

  LeadershipStatus get status {
    if (confirmedAt != null) return LeadershipStatus.confirmed;
    if (rejectedAt != null) return LeadershipStatus.rejected;
    return LeadershipStatus.pending;
  }

  /// FR-008: a confirmação só conta como atual pro ano em que foi feita —
  /// sem job agendado, comparação preguiçosa contra o ano informado.
  bool isCurrentFor(int year) {
    return status == LeadershipStatus.confirmed && this.year == year;
  }

  factory LeadershipDeclaration.fromMap(Map<String, dynamic> map) {
    return LeadershipDeclaration(
      id: map['id'] as String,
      groupId: map['grupo_id'] as String,
      userId: map['usuario_id'] as String,
      year: map['ano'] as int,
      declaredAt: DateTime.parse(map['declarado_em'] as String),
      confirmedBy: map['confirmado_por'] as String?,
      confirmedAt: map['confirmado_em'] == null
          ? null
          : DateTime.parse(map['confirmado_em'] as String),
      rejectedAt: map['rejeitado_em'] == null
          ? null
          : DateTime.parse(map['rejeitado_em'] as String),
    );
  }
}

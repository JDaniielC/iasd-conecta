/// Dados de uma Rodada de votação ainda não enviada ao banco (formulário de
/// abertura). `grupoId`/`abertaPor` são preenchidos pelo repositório a
/// partir do contexto/sessão atual.
class NewVotingRound {
  const NewVotingRound({required this.deadline});

  final DateTime deadline;

  bool get isReadyToSubmit => deadline.isAfter(DateTime.now());

  Map<String, dynamic> toInsertMap({required String groupId, required String openedBy}) {
    return {
      'grupo_id': groupId,
      'aberta_por': openedBy,
      'prazo': deadline.toUtc().toIso8601String(),
    };
  }
}

class VotingRound {
  const VotingRound({
    required this.id,
    required this.groupId,
    required this.openedBy,
    required this.deadline,
    this.closedAt,
    this.winnerId,
  });

  final String id;
  final String groupId;
  final String openedBy;
  final DateTime deadline;
  final DateTime? closedAt;
  final String? winnerId;

  bool get isOpen => closedAt == null;

  factory VotingRound.fromMap(Map<String, dynamic> map) {
    return VotingRound(
      id: map['id'] as String,
      groupId: map['grupo_id'] as String,
      openedBy: map['aberta_por'] as String,
      deadline: DateTime.parse(map['prazo'] as String),
      closedAt: map['fechada_em'] == null ? null : DateTime.parse(map['fechada_em'] as String),
      winnerId: map['vencedora_id'] as String?,
    );
  }
}

class Vote {
  const Vote({required this.userId, required this.candidateId});

  final String userId;
  final String candidateId;

  factory Vote.fromMap(Map<String, dynamic> map) {
    return Vote(
      userId: map['usuario_id'] as String,
      candidateId: map['candidata_id'] as String,
    );
  }
}

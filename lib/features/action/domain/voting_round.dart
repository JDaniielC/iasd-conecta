/// Dados de uma Rodada de votação ainda não enviada ao banco (formulário de
/// abertura). `grupoId`/`abertaPor` são preenchidos pelo repositório a
/// partir do contexto/sessão atual.
class NewVotingRound {
  const NewVotingRound({required this.deadline});

  final DateTime deadline;

  bool get isReadyToSubmit => deadline.isAfter(DateTime.now());

  Map<String, dynamic> toInsertMap({required String grupoId, required String abertaPor}) {
    return {
      'grupo_id': grupoId,
      'aberta_por': abertaPor,
      'prazo': deadline.toUtc().toIso8601String(),
    };
  }
}

class VotingRound {
  const VotingRound({
    required this.id,
    required this.grupoId,
    required this.abertaPor,
    required this.deadline,
    this.fechadaEm,
    this.vencedoraId,
  });

  final String id;
  final String grupoId;
  final String abertaPor;
  final DateTime deadline;
  final DateTime? fechadaEm;
  final String? vencedoraId;

  bool get aberta => fechadaEm == null;

  factory VotingRound.fromMap(Map<String, dynamic> map) {
    return VotingRound(
      id: map['id'] as String,
      grupoId: map['grupo_id'] as String,
      abertaPor: map['aberta_por'] as String,
      deadline: DateTime.parse(map['prazo'] as String),
      fechadaEm: map['fechada_em'] == null ? null : DateTime.parse(map['fechada_em'] as String),
      vencedoraId: map['vencedora_id'] as String?,
    );
  }
}

class Vote {
  const Vote({required this.usuarioId, required this.candidataId});

  final String usuarioId;
  final String candidataId;

  factory Vote.fromMap(Map<String, dynamic> map) {
    return Vote(
      usuarioId: map['usuario_id'] as String,
      candidataId: map['candidata_id'] as String,
    );
  }
}

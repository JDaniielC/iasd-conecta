/// Dados de uma Rodada de votação ainda não enviada ao banco (formulário de
/// abertura). `grupoId`/`abertaPor` são preenchidos pelo repositório a
/// partir do contexto/sessão atual.
class NovaRodada {
  const NovaRodada({required this.prazo});

  final DateTime prazo;

  bool get prontoParaEnviar => prazo.isAfter(DateTime.now());

  Map<String, dynamic> toInsertMap({required String grupoId, required String abertaPor}) {
    return {
      'grupo_id': grupoId,
      'aberta_por': abertaPor,
      'prazo': prazo.toUtc().toIso8601String(),
    };
  }
}

class Rodada {
  const Rodada({
    required this.id,
    required this.grupoId,
    required this.abertaPor,
    required this.prazo,
    this.fechadaEm,
    this.vencedoraId,
  });

  final String id;
  final String grupoId;
  final String abertaPor;
  final DateTime prazo;
  final DateTime? fechadaEm;
  final String? vencedoraId;

  bool get aberta => fechadaEm == null;

  factory Rodada.fromMap(Map<String, dynamic> map) {
    return Rodada(
      id: map['id'] as String,
      grupoId: map['grupo_id'] as String,
      abertaPor: map['aberta_por'] as String,
      prazo: DateTime.parse(map['prazo'] as String),
      fechadaEm: map['fechada_em'] == null ? null : DateTime.parse(map['fechada_em'] as String),
      vencedoraId: map['vencedora_id'] as String?,
    );
  }
}

class Voto {
  const Voto({required this.usuarioId, required this.candidataId});

  final String usuarioId;
  final String candidataId;

  factory Voto.fromMap(Map<String, dynamic> map) {
    return Voto(
      usuarioId: map['usuario_id'] as String,
      candidataId: map['candidata_id'] as String,
    );
  }
}

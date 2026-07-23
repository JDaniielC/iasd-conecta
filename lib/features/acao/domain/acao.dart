import '../../perfil/domain/perfil.dart';

/// Dados de uma Ação avulsa ainda não enviada ao banco (formulário de
/// criação). `criadorId` é preenchido pelo repositório a partir da sessão
/// atual (FR-001/FR-013).
class NovaAcao {
  const NovaAcao({
    required this.nome,
    required this.dataHora,
    required this.local,
    this.detalhes,
    this.limiteVagas,
  });

  final String nome;
  final DateTime dataHora;
  final String local;
  final String? detalhes;
  final int? limiteVagas;

  bool get prontoParaEnviar =>
      nome.trim().isNotEmpty &&
      local.trim().isNotEmpty &&
      (limiteVagas == null || limiteVagas! > 0);

  Map<String, dynamic> toInsertMap({required String criadorId}) {
    return {
      'nome': nome.trim(),
      'data_hora': dataHora.toUtc().toIso8601String(),
      'local': local.trim(),
      'detalhes': (detalhes?.trim().isEmpty ?? true) ? null : detalhes!.trim(),
      'limite_vagas': limiteVagas,
      'criador_id': criadorId,
    };
  }
}

class Acao {
  const Acao({
    required this.id,
    required this.nome,
    required this.dataHora,
    required this.local,
    required this.criadorId,
    this.detalhes,
    this.limiteVagas,
    this.canceladaEm,
  });

  final String id;
  final String nome;
  final DateTime dataHora;
  final String local;
  final String? detalhes;
  final int? limiteVagas;
  final String criadorId;
  final DateTime? canceladaEm;

  bool get cancelada => canceladaEm != null;

  bool souCriador(String? usuarioAtualId) =>
      usuarioAtualId != null && usuarioAtualId == criadorId;

  factory Acao.fromMap(Map<String, dynamic> map) {
    return Acao(
      id: map['id'] as String,
      nome: map['nome'] as String,
      dataHora: DateTime.parse(map['data_hora'] as String),
      local: map['local'] as String,
      detalhes: map['detalhes'] as String?,
      limiteVagas: map['limite_vagas'] as int?,
      criadorId: map['criador_id'] as String,
      canceladaEm:
          map['cancelada_em'] == null ? null : DateTime.parse(map['cancelada_em'] as String),
    );
  }
}

enum StatusConfirmacao { confirmado, fila }

class ConfirmacaoComPerfil {
  const ConfirmacaoComPerfil({required this.perfil, required this.status});

  final PerfilPublico perfil;
  final StatusConfirmacao status;
}

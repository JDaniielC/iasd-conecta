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
    this.rodadaId,
  });

  final String nome;
  final DateTime dataHora;
  final String local;
  final String? detalhes;
  final int? limiteVagas;

  /// Preenchido só quando esta Ação é uma candidata proposta numa Rodada de
  /// votação (feature 004) — `grupo_id` nunca é enviado pelo client, é
  /// sempre derivado da Rodada pelo trigger `acoes_candidata_checar_regras`.
  final String? rodadaId;

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
      if (rodadaId != null) 'rodada_id': rodadaId,
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
    this.grupoId,
    this.rodadaId,
    this.confirmada = true,
  });

  final String id;
  final String nome;
  final DateTime dataHora;
  final String local;
  final String? detalhes;
  final int? limiteVagas;
  final String criadorId;
  final DateTime? canceladaEm;

  /// Não-nulo quando é uma Ação de Grupo (candidata ou já confirmada).
  final String? grupoId;

  /// Não-nulo enquanto esta Ação é uma candidata numa Rodada de votação.
  final String? rodadaId;

  /// `false` só enquanto é candidata em votação; sempre `true` pra Ação
  /// avulsa e pra Ação de Grupo já vencedora (feature 004).
  final bool confirmada;

  bool get cancelada => canceladaEm != null;

  bool get ehCandidataEmVotacao => !confirmada;

  bool souCriador(String? usuarioAtualId) =>
      usuarioAtualId != null && usuarioAtualId == criadorId;

  /// FR-016: quem propôs (criador) OU o Dono do Grupo cancela uma Ação de
  /// Grupo. `souDonoDoGrupo` é resolvido por quem chama (o repositório sabe
  /// quem é o Dono do `grupoId`), não pelo modelo em si.
  bool podeCancelar(String? usuarioAtualId, {required bool souDonoDoGrupo}) =>
      souCriador(usuarioAtualId) || (grupoId != null && souDonoDoGrupo);

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
      grupoId: map['grupo_id'] as String?,
      rodadaId: map['rodada_id'] as String?,
      confirmada: map['confirmada'] as bool? ?? true,
    );
  }
}

enum StatusConfirmacao { confirmado, fila }

class ConfirmacaoComPerfil {
  const ConfirmacaoComPerfil({required this.perfil, required this.status});

  final PerfilPublico perfil;
  final StatusConfirmacao status;
}

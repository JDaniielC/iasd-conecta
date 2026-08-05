import '../../perfil/domain/perfil.dart';

/// Dados de uma Ação avulsa ainda não enviada ao banco (formulário de
/// criação). `criadorId` é preenchido pelo repositório a partir da sessão
/// atual (FR-001/FR-013).
enum VisitedGender { male, female }

class NovaAcao {
  const NovaAcao({
    required this.nome,
    required this.dataHora,
    required this.local,
    this.detalhes,
    this.limiteVagas,
    this.rodadaId,
    this.isMissionaryPair = false,
    this.visitedGender,
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

  /// Dupla Missionária (feature 007): quando `true`, exige [visitedGender]
  /// e o limite de vagas é sempre 2, ignorando [limiteVagas] informado.
  final bool isMissionaryPair;
  final VisitedGender? visitedGender;

  bool get prontoParaEnviar =>
      nome.trim().isNotEmpty &&
      local.trim().isNotEmpty &&
      (limiteVagas == null || limiteVagas! > 0) &&
      (!isMissionaryPair || visitedGender != null);

  Map<String, dynamic> toInsertMap({required String criadorId}) {
    return {
      'nome': nome.trim(),
      'data_hora': dataHora.toUtc().toIso8601String(),
      'local': local.trim(),
      'detalhes': (detalhes?.trim().isEmpty ?? true) ? null : detalhes!.trim(),
      'limite_vagas': isMissionaryPair ? 2 : limiteVagas,
      'criador_id': criadorId,
      if (rodadaId != null) 'rodada_id': rodadaId,
      'eh_dupla_missionaria': isMissionaryPair,
      'genero_visitado': switch (visitedGender) {
        VisitedGender.male => 'masculino',
        VisitedGender.female => 'feminino',
        null => null,
      },
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
    required this.createdAt,
    this.detalhes,
    this.limiteVagas,
    this.canceladaEm,
    this.grupoId,
    this.rodadaId,
    this.confirmada = true,
    this.isMissionaryPair = false,
    this.visitedGender,
  });

  final String id;
  final String nome;
  final DateTime dataHora;
  final String local;
  final String? detalhes;
  final int? limiteVagas;
  final String criadorId;
  final DateTime createdAt;
  final DateTime? canceladaEm;

  /// Não-nulo quando é uma Ação de Grupo (candidata ou já confirmada).
  final String? grupoId;

  /// Não-nulo enquanto esta Ação é uma candidata numa Rodada de votação.
  final String? rodadaId;

  /// `false` só enquanto é candidata em votação; sempre `true` pra Ação
  /// avulsa e pra Ação de Grupo já vencedora (feature 004).
  final bool confirmada;

  /// Dupla Missionária (feature 007): composição de gênero validada no
  /// banco a cada confirmação de presença (ver migration).
  final bool isMissionaryPair;
  final VisitedGender? visitedGender;

  bool get cancelada => canceladaEm != null;

  bool get ehCandidataEmVotacao => !confirmada;

  bool souCriador(String? usuarioAtualId) =>
      usuarioAtualId != null && usuarioAtualId == criadorId;

  /// FR-016 (004): quem propôs (criador) OU o Dono do Grupo cancela uma
  /// Ação de Grupo. FR-009 (005): Administrador do distrito cancela
  /// qualquer Ação. Ambos os booleanos são resolvidos por quem chama (o
  /// repositório/provider sabe quem é o Dono do `grupoId` e quem é
  /// Administrador), não pelo modelo em si.
  bool podeCancelar(
    String? usuarioAtualId, {
    required bool souDonoDoGrupo,
    bool souAdministradorDoDistrito = false,
  }) =>
      souAdministradorDoDistrito ||
      souCriador(usuarioAtualId) ||
      (grupoId != null && souDonoDoGrupo);

  factory Acao.fromMap(Map<String, dynamic> map) {
    return Acao(
      id: map['id'] as String,
      nome: map['nome'] as String,
      dataHora: DateTime.parse(map['data_hora'] as String),
      local: map['local'] as String,
      detalhes: map['detalhes'] as String?,
      limiteVagas: map['limite_vagas'] as int?,
      criadorId: map['criador_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      canceladaEm:
          map['cancelada_em'] == null ? null : DateTime.parse(map['cancelada_em'] as String),
      grupoId: map['grupo_id'] as String?,
      rodadaId: map['rodada_id'] as String?,
      confirmada: map['confirmada'] as bool? ?? true,
      isMissionaryPair: map['eh_dupla_missionaria'] as bool? ?? false,
      visitedGender: switch (map['genero_visitado'] as String?) {
        'masculino' => VisitedGender.male,
        'feminino' => VisitedGender.female,
        _ => null,
      },
    );
  }
}

/// Ação com a Igreja já resolvida — via `grupos.igreja_id` (Ação de Grupo)
/// ou `perfis.igreja_id` do criador (Ação avulsa). Usado só pra agrupar/
/// filtrar a lista por Igreja; a Ação em si não guarda `igreja_id`.
class AcaoComIgreja {
  const AcaoComIgreja({required this.acao, this.igrejaId});

  final Acao acao;
  final String? igrejaId;
}

enum PeriodoAcao { sabado, hoje, essaSemana, outras }

/// Sábado adventista: sexta 17:30 até sábado 17:30 — aproximação de
/// pôr-do-sol por horário fixo (não calcula pôr-do-sol real por data/local).
bool acaoNoSabado(DateTime dataHora) {
  final minutosDoDia = dataHora.hour * 60 + dataHora.minute;
  const inicioSabado = 17 * 60 + 30;
  if (dataHora.weekday == DateTime.friday) return minutosDoDia >= inicioSabado;
  if (dataHora.weekday == DateTime.saturday) return minutosDoDia < inicioSabado;
  return false;
}

DateTime _inicioDaSemana(DateTime data) {
  final dia = DateTime(data.year, data.month, data.day);
  // Semana começa domingo (weekday: seg=1 ... dom=7 -> dom vira 0).
  return dia.subtract(Duration(days: dia.weekday % 7));
}

/// Classifica [dataHora] em relação a [agora] pra agrupar `ListaAcoesPage`
/// por período. Sábado tem prioridade sobre Hoje/Essa semana — é o destaque
/// que a comunidade adventista mais procura, mesmo caindo também "hoje".
PeriodoAcao periodoDaAcao(DateTime dataHora, DateTime agora) {
  if (acaoNoSabado(dataHora)) return PeriodoAcao.sabado;

  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(dataHora.year, dataHora.month, dataHora.day);
  if (dia == hoje) return PeriodoAcao.hoje;

  final inicioSemana = _inicioDaSemana(agora);
  final fimSemana = inicioSemana.add(const Duration(days: 7));
  if (!dataHora.isBefore(inicioSemana) && dataHora.isBefore(fimSemana)) {
    return PeriodoAcao.essaSemana;
  }

  return PeriodoAcao.outras;
}

enum StatusConfirmacao { confirmado, fila }

class ConfirmacaoComPerfil {
  const ConfirmacaoComPerfil({required this.perfil, required this.status});

  final PerfilPublico perfil;
  final StatusConfirmacao status;
}

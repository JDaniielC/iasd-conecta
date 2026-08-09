import '../../profile/domain/profile.dart';

/// Dados de uma Ação avulsa ainda não enviada ao banco (formulário de
/// criação). `criadorId` é preenchido pelo repositório a partir da sessão
/// atual (FR-001/FR-013).
enum VisitedGender { male, female }

class NewAction {
  const NewAction({
    required this.name,
    required this.dateTime,
    required this.local,
    this.details,
    this.capacity,
    this.votingRoundId,
    this.isMissionaryPair = false,
    this.visitedGender,
  });

  final String name;
  final DateTime dateTime;
  final String local;
  final String? details;
  final int? capacity;

  /// Preenchido só quando esta Ação é uma candidata proposta numa Rodada de
  /// votação (feature 004) — `grupo_id` nunca é enviado pelo client, é
  /// sempre derivado da Rodada pelo trigger `acoes_candidata_checar_regras`.
  final String? votingRoundId;

  /// Dupla Missionária (feature 007): quando `true`, exige [visitedGender]
  /// e o limite de vagas é sempre 2, ignorando [limiteVagas] informado.
  final bool isMissionaryPair;
  final VisitedGender? visitedGender;

  bool get isReadyToSubmit =>
      name.trim().isNotEmpty &&
      local.trim().isNotEmpty &&
      (capacity == null || capacity! > 0) &&
      (!isMissionaryPair || visitedGender != null);

  Map<String, dynamic> toInsertMap({required String creatorId}) {
    return {
      'nome': name.trim(),
      'data_hora': dateTime.toUtc().toIso8601String(),
      'local': local.trim(),
      'detalhes': (details?.trim().isEmpty ?? true) ? null : details!.trim(),
      'limite_vagas': isMissionaryPair ? 2 : capacity,
      'criador_id': creatorId,
      if (votingRoundId != null) 'rodada_id': votingRoundId,
      'eh_dupla_missionaria': isMissionaryPair,
      'genero_visitado': switch (visitedGender) {
        VisitedGender.male => 'masculino',
        VisitedGender.female => 'feminino',
        null => null,
      },
    };
  }
}

class Action {
  const Action({
    required this.id,
    required this.name,
    required this.dateTime,
    required this.local,
    required this.creatorId,
    required this.createdAt,
    this.details,
    this.capacity,
    this.cancelledAt,
    this.groupId,
    this.votingRoundId,
    this.isConfirmed = true,
    this.isMissionaryPair = false,
    this.visitedGender,
  });

  final String id;
  final String name;
  final DateTime dateTime;
  final String local;
  final String? details;
  final int? capacity;
  final String creatorId;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  /// Não-nulo quando é uma Ação de Grupo (candidata ou já confirmada).
  final String? groupId;

  /// Não-nulo enquanto esta Ação é uma candidata numa Rodada de votação.
  final String? votingRoundId;

  /// `false` só enquanto é candidata em votação; sempre `true` pra Ação
  /// avulsa e pra Ação de Grupo já vencedora (feature 004).
  final bool isConfirmed;

  /// Dupla Missionária (feature 007): composição de gênero validada no
  /// banco a cada confirmação de presença (ver migration).
  final bool isMissionaryPair;
  final VisitedGender? visitedGender;

  bool get isCancelled => cancelledAt != null;

  bool get isCandidateInVoting => !isConfirmed;

  bool isCreator(String? currentUserId) =>
      currentUserId != null && currentUserId == creatorId;

  /// FR-016 (004): quem propôs (criador) OU o Dono do Grupo cancela uma
  /// Ação de Grupo. FR-009 (005): Administrador do distrito cancela
  /// qualquer Ação. Ambos os booleanos são resolvidos por quem chama (o
  /// repositório/provider sabe quem é o Dono do `grupoId` e quem é
  /// Administrador), não pelo modelo em si.
  bool canCancel(
    String? currentUserId, {
    required bool isGroupOwner,
    bool isDistrictAdmin = false,
  }) =>
      isDistrictAdmin ||
      isCreator(currentUserId) ||
      (groupId != null && isGroupOwner);

  factory Action.fromMap(Map<String, dynamic> map) {
    return Action(
      id: map['id'] as String,
      name: map['nome'] as String,
      dateTime: DateTime.parse(map['data_hora'] as String),
      local: map['local'] as String,
      details: map['detalhes'] as String?,
      capacity: map['limite_vagas'] as int?,
      creatorId: map['criador_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      cancelledAt:
          map['cancelada_em'] == null ? null : DateTime.parse(map['cancelada_em'] as String),
      groupId: map['grupo_id'] as String?,
      votingRoundId: map['rodada_id'] as String?,
      isConfirmed: map['confirmada'] as bool? ?? true,
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
class ActionWithChurch {
  const ActionWithChurch({required this.action, this.churchId});

  final Action action;
  final String? churchId;
}

/// Quanto tempo uma Ação fica "acontecendo agora" depois da hora marcada.
///
/// A Ação não guarda hora de término — este é o padrão para todas (FR-001).
/// **Tem gêmea em SQL**: `interval '4 hours'` dentro de `public.acao_encerrada`
/// (migration `_acao_encerrada_bloqueia_presenca.sql`). Mudar uma sem a outra dá
/// o sintoma cruel: o botão some na tela mas o banco ainda aceita, ou o
/// contrário. Ao mexer aqui, mexer lá e rodar os dois testes de fronteira.
const defaultActionDuration = Duration(hours: 4);

/// Estado de uma Ação no tempo — derivado, nunca gravado.
enum ActionTimeStatus {
  /// Ainda vai acontecer.
  upcoming,

  /// Entre a hora marcada e [defaultActionDuration] depois dela. Continua na
  /// listagem e ainda aceita confirmar e desistir (FR-002) — quem está a
  /// caminho precisa achá-la.
  happeningNow,

  /// Passou de `dateTime + defaultActionDuration`. Some da listagem (FR-003),
  /// continua acessível por link (FR-004), e não aceita mais confirmar nem
  /// desistir (FR-005).
  ended,
}

/// Classifica a Ação no tempo. Função pura: não grava nada, não agenda nada.
///
/// Gravar um estado que só depende do relógio criaria a obrigação de mantê-lo
/// atualizado — job, cron ou trigger — e a garantia de que um dia ficaria
/// defasado. A informação já está em `dateTime`.
///
/// Fronteira: em `dateTime + defaultActionDuration` cravado ainda é
/// [ActionTimeStatus.happeningNow]; encerra no primeiro instante depois.
ActionTimeStatus actionTimeStatus(DateTime dateTime, DateTime now) {
  if (now.isBefore(dateTime)) return ActionTimeStatus.upcoming;
  if (now.isAfter(dateTime.add(defaultActionDuration))) {
    return ActionTimeStatus.ended;
  }
  return ActionTimeStatus.happeningNow;
}

enum ActionPeriod { sabbath, hoje, essaSemana, outras }

/// Sábado adventista: sexta 17:30 até sábado 17:30 — aproximação de
/// pôr-do-sol por horário fixo (não calcula pôr-do-sol real por data/local).
bool isOnSabbath(DateTime dateTime) {
  final minutosDoDia = dateTime.hour * 60 + dateTime.minute;
  const sabbathStart = 17 * 60 + 30;
  if (dateTime.weekday == DateTime.friday) return minutosDoDia >= sabbathStart;
  if (dateTime.weekday == DateTime.saturday) return minutosDoDia < sabbathStart;
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
ActionPeriod actionPeriod(DateTime dateTime, DateTime now) {
  if (isOnSabbath(dateTime)) return ActionPeriod.sabbath;

  final hoje = DateTime(now.year, now.month, now.day);
  final dia = DateTime(dateTime.year, dateTime.month, dateTime.day);
  if (dia == hoje) return ActionPeriod.hoje;

  final inicioSemana = _inicioDaSemana(now);
  final fimSemana = inicioSemana.add(const Duration(days: 7));
  if (!dateTime.isBefore(inicioSemana) && dateTime.isBefore(fimSemana)) {
    return ActionPeriod.essaSemana;
  }

  return ActionPeriod.outras;
}

enum AttendanceStatus { confirmed, waitlist }

/// Contagem agregada de presenças de uma Ação, para a listagem (FR-009).
///
/// [waiting] **nunca** é somado a [confirmed]: somar faria uma Ação de 10
/// vagas parecer ter 15 participantes.
class ConfirmationCounts {
  const ConfirmationCounts({this.confirmed = 0, this.waiting = 0});

  /// Quem tem vaga.
  final int confirmed;

  /// Quem está na fila de espera.
  final int waiting;
}

class AttendanceWithProfile {
  const AttendanceWithProfile({required this.profile, required this.status});

  final PublicProfile profile;
  final AttendanceStatus status;
}

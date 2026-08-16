import '../../profile/domain/profile.dart';

/// Dados de uma Ação avulsa ainda não enviada ao banco (formulário de
/// criação). `criadorId` é preenchido pelo repositório a partir da sessão
/// atual (FR-001/FR-013).
enum VisitedGender { male, female }

class NewAction {
  const NewAction({
    required this.name,
    required this.dateTime,
    required this.location,
    this.details,
    this.capacity,
    this.votingRoundId,
    this.isMissionaryPair = false,
    this.visitedGender,
    this.restrictedToGroup = false,
  });

  final String name;
  final DateTime dateTime;
  final String location;
  final String? details;
  final int? capacity;

  /// Preenchido só quando esta Ação é uma candidata proposta numa Rodada de
  /// votação (feature 004) — `grupo_id` nunca é enviado pelo client, é
  /// sempre derivado da Rodada pelo trigger `acoes_candidata_checar_regras`.
  final String? votingRoundId;

  /// Dupla Missionária (feature 007): quando `true`, exige [visitedGender]
  /// e o limite de vagas é sempre 2, ignorando [capacity] informado.
  final bool isMissionaryPair;
  final VisitedGender? visitedGender;

  /// Ação visível só para quem participa do Grupo (change
  /// `acao-direcionada-a-grupo`). Só faz sentido com [votingRoundId]: Ação de
  /// Grupo neste app é candidata de Rodada, e o `check`
  /// `acoes_restrita_exige_grupo` recusa a combinação sem Grupo.
  final bool restrictedToGroup;

  bool get isReadyToSubmit =>
      name.trim().isNotEmpty &&
      location.trim().isNotEmpty &&
      (capacity == null || capacity! > 0) &&
      (!isMissionaryPair || visitedGender != null);

  Map<String, dynamic> toInsertMap({required String creatorId}) {
    return {
      'nome': name.trim(),
      'data_hora': dateTime.toUtc().toIso8601String(),
      'local': location.trim(),
      'detalhes': (details?.trim().isEmpty ?? true) ? null : details!.trim(),
      'limite_vagas': isMissionaryPair ? 2 : capacity,
      'criador_id': creatorId,
      if (votingRoundId != null) 'rodada_id': votingRoundId,
      // Só vai junto quando há Rodada. Numa Ação avulsa a chave nem é enviada:
      // mandar `false` seria inofensivo, mas mandar `true` bateria no `check`
      // do banco, e é melhor o formulário não ter como formar a combinação.
      if (votingRoundId != null) 'restrita_ao_grupo': restrictedToGroup,
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
    required this.location,
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
    this.restrictedToGroup = false,
  });

  final String id;
  final String name;
  final DateTime dateTime;
  final String location;
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

  /// Ação visível só para quem participa do Grupo dela.
  ///
  /// Isto é marca de tela, NUNCA filtro: quando esta Ação chegou até aqui, o
  /// banco já decidiu que quem está lendo pode vê-la (`acoes_select_visivel`).
  /// Filtrar de novo no cliente seria uma segunda regra para divergir da
  /// primeira.
  final bool restrictedToGroup;

  bool get isCancelled => cancelledAt != null;

  /// Quem pode marcar/desmarcar a restrição: a mesma gente que edita a Ação,
  /// por `acoes_update_criador_dono_grupo_ou_admin`. Só faz sentido em Ação de
  /// Grupo, e o banco recusa a mudança depois de encerrada.
  bool canRestrict(
    String? currentUserId, {
    required bool isGroupOwner,
    bool isDistrictAdmin = false,
  }) =>
      groupId != null &&
      (isDistrictAdmin || isCreator(currentUserId) || isGroupOwner);

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
      location: map['local'] as String,
      details: map['detalhes'] as String?,
      capacity: map['limite_vagas'] as int?,
      creatorId: map['criador_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      cancelledAt:
          map['cancelada_em'] == null ? null : DateTime.parse(map['cancelada_em'] as String),
      groupId: map['grupo_id'] as String?,
      votingRoundId: map['rodada_id'] as String?,
      isConfirmed: map['confirmada'] as bool? ?? true,
      restrictedToGroup: map['restrita_ao_grupo'] as bool? ?? false,
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

enum ActionPeriod { sabbath, today, thisWeek, other }

/// Sábado adventista: sexta 17:30 até sábado 17:30 — aproximação de
/// pôr-do-sol por horário fixo (não calcula pôr-do-sol real por data/local).
bool isOnSabbath(DateTime dateTime) {
  final minutesOfDay = dateTime.hour * 60 + dateTime.minute;
  const sabbathStart = 17 * 60 + 30;
  if (dateTime.weekday == DateTime.friday) return minutesOfDay >= sabbathStart;
  if (dateTime.weekday == DateTime.saturday) return minutesOfDay < sabbathStart;
  return false;
}

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  // Semana começa domingo (weekday: seg=1 ... dom=7 -> dom vira 0).
  return day.subtract(Duration(days: day.weekday % 7));
}

/// Classifica [dateTime] em relação a [now] pra agrupar `ActionListPage`
/// por período. Sábado tem prioridade sobre Hoje/Essa semana — é o destaque
/// que a comunidade adventista mais procura, mesmo caindo também "hoje".
ActionPeriod actionPeriod(DateTime dateTime, DateTime now) {
  if (isOnSabbath(dateTime)) return ActionPeriod.sabbath;

  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  if (day == today) return ActionPeriod.today;

  final weekStart = _startOfWeek(now);
  final weekEnd = weekStart.add(const Duration(days: 7));
  if (!dateTime.isBefore(weekStart) && dateTime.isBefore(weekEnd)) {
    return ActionPeriod.thisWeek;
  }

  return ActionPeriod.other;
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

/// Normaliza para comparar nome de Ação com nome de pessoa: tira espaço das
/// pontas, colapsa espaço interno, baixa a caixa e remove acentuação.
///
/// A remoção de acento é feita à mão porque não existe pronta na base — a
/// `NameModeration` do módulo de Perfil só faz `toLowerCase`, e trazer
/// dependência nova para isto seria desproporcional.
String normalizeForNameComparison(String text) {
  const accented = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const unaccented = 'aaaaaeeeeiiiiooooouuuucn';

  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final i = accented.indexOf(char);
    buffer.write(i == -1 ? char : unaccented[i]);
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// O nome digitado é o nome da própria pessoa que está criando? (FR-017)
///
/// É **igualdade** após normalizar, nunca `contains`: "Visita a José" é nome
/// legítimo de atividade e não pode ser barrado (FR-019).
///
/// [creatorDisplayName] é o nome de **exibição** — para menor de idade, a RPC
/// `perfil_publico` devolve o Apelido, e FR-017 pede que o Apelido também seja
/// recusado. Quando ele é nulo ou vazio (sem rede, RPC falhando), a resposta é
/// `false`: recusar por falta de dado transformaria um problema de conexão numa
/// acusação ao Usuário.
bool isCreatorOwnName(String actionName, String? creatorDisplayName) {
  if (creatorDisplayName == null || creatorDisplayName.trim().isEmpty) {
    return false;
  }
  return normalizeForNameComparison(actionName) ==
      normalizeForNameComparison(creatorDisplayName);
}

/// Por que uma Ação está na faixa de destaque de `/acoes`.
///
/// Dimensão independente do Sábado (`ActionPeriod.sabbath`): aquele diz
/// **quando** a Ação acontece, este diz **de onde** ela vem. As duas valem ao
/// mesmo tempo para a mesma Ação, e a tela precisa mostrar os dois sinais sem
/// que virem a mesma cor.
enum ActionHighlight {
  /// Ação avulsa — sem Grupo. Alcança o distrito inteiro, então entra no
  /// destaque para qualquer pessoa, com ou sem Perfil, e nunca deixa de
  /// entrar (não tem "já vi").
  district,

  /// Ação de um Grupo de que quem está vendo participa, criada depois da
  /// última vez que essa pessoa abriu `/acoes`. Some do destaque na abertura
  /// seguinte.
  myGroup,
}

/// Por que [action] entra na faixa de destaque — ou `null` se não entra.
///
/// [lastSeen] nulo é instalação nova, e a resposta é `null` de propósito, não
/// por falta de dado: para quem chega agora o app inteiro é novo, e apontar
/// uma parte dele como novidade não quer dizer nada. É o mesmo dos três
/// comportamentos de `hasUnseenNewsProvider`.
///
/// Ação de Grupo ainda em votação (`isConfirmed == false`) nunca entra: a
/// spec fala de Ação de Grupo **confirmada**, e uma candidata pode nem
/// existir depois da apuração.
///
/// Ação cancelada também não entra, nem sendo avulsa. Ela continua na lista
/// por período marcada como "Cancelada" (FR-003 só tira a encerrada por
/// tempo), mas promover ao topo da tela uma Ação que não vai acontecer é
/// convidar para o que já foi desmarcado.
ActionHighlight? actionHighlight(
  Action action, {
  required Set<String> myGroupIds,
  required DateTime? lastSeen,
}) {
  if (action.isCancelled) return null;
  if (action.groupId == null) return ActionHighlight.district;
  if (!action.isConfirmed) return null;
  if (!myGroupIds.contains(action.groupId)) return null;
  if (lastSeen == null) return null;
  return action.createdAt.isAfter(lastSeen) ? ActionHighlight.myGroup : null;
}

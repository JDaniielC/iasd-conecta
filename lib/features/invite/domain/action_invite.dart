import '../../action/domain/action.dart';

/// Uma linha de `convites_acao` (change `convite-para-acao`).
///
/// Não existe campo de aceite de propósito: aceitar é confirmar presença, e
/// isso é `confirmacoes_acao`. Um `status = 'aceito'` aqui seria a segunda
/// fonte de verdade sobre a mesma coisa, e as duas divergiriam no primeiro
/// "desistir".
///
/// As chaves do mapa são as do banco, em português; os identificadores Dart são
/// em inglês. É a fronteira de idioma do `CONTEXT.md`, não inconsistência.
class ActionInvite {
  const ActionInvite({
    required this.actionId,
    required this.invitedId,
    required this.groupId,
    required this.inviterId,
    required this.createdAt,
    this.declinedAt,
  });

  final String actionId;
  final String invitedId;

  /// O Grupo pelo qual o convite foi feito. Está na chave primária: a mesma
  /// pessoa convidada para a mesma Ação por dois Grupos são dois convites, e é
  /// por este campo que quem recebeu filtra.
  final String groupId;
  final String inviterId;
  final DateTime createdAt;
  final DateTime? declinedAt;

  bool get isDeclined => declinedAt != null;

  factory ActionInvite.fromMap(Map<String, dynamic> map) {
    return ActionInvite(
      actionId: map['acao_id'] as String,
      invitedId: map['convidado_id'] as String,
      groupId: map['grupo_id'] as String,
      inviterId: map['convidante_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      declinedAt: map['recusado_em'] == null
          ? null
          : DateTime.parse(map['recusado_em'] as String),
    );
  }
}

/// Convite como quem recebeu enxerga: a linha, a Ação para onde ele aponta, o
/// nome do Grupo de origem, e se essa pessoa já confirmou presença.
class ReceivedInvite {
  const ReceivedInvite({
    required this.invite,
    required this.groupName,
    required this.action,
    required this.alreadyConfirmed,
  });

  final ActionInvite invite;
  final String groupName;

  /// Nulo quando a Ação não é legível para quem recebeu — acontece com Ação
  /// restrita ao Grupo depois que a pessoa sai dele (`acoes_select_visivel`).
  /// Convite apontando para o que não abre é tratado como convite morto.
  final Action? action;
  final bool alreadyConfirmed;

  /// "Em aberto" é DERIVADO, não guardado: a linha existe, não foi recusada, a
  /// pessoa ainda não confirmou, e a Ação está viva e visível.
  bool isOpen(DateTime now) {
    final a = action;
    if (invite.isDeclined) return false;
    if (alreadyConfirmed) return false;
    if (a == null) return false;
    if (a.isCancelled) return false;
    return actionTimeStatus(a.dateTime, now) != ActionTimeStatus.ended;
  }
}

/// O que aconteceu com cada pessoa de um lote de convites.
enum InviteOutcome {
  /// Convite criado agora.
  created,

  /// Já existia convite dessa pessoa, por esse Grupo, para essa Ação. Repetir
  /// não é erro — a tela não pode ler isso como falha.
  alreadyInvited,

  /// A pessoa não participa do Grupo pelo qual o convite foi tentado.
  notInGroup,
}

/// Resultado por pessoa. O lote devolve UMA LINHA POR PESSOA PEDIDA, para a
/// tela poder dizer nominalmente quem ficou de fora.
class InviteResult {
  const InviteResult({required this.userId, required this.outcome});

  final String userId;
  final InviteOutcome outcome;

  bool get succeeded =>
      outcome == InviteOutcome.created || outcome == InviteOutcome.alreadyInvited;

  factory InviteResult.fromMap(Map<String, dynamic> map) {
    return InviteResult(
      userId: map['usuario_id'] as String,
      outcome: switch (map['resultado'] as String) {
        'criado' => InviteOutcome.created,
        'ja_convidado' => InviteOutcome.alreadyInvited,
        'nao_participa' => InviteOutcome.notInGroup,
        final other => throw ArgumentError('resultado desconhecido: $other'),
      },
    );
  }
}

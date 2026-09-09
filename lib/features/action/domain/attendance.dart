import '../../profile/domain/profile.dart';

/// Uma linha da lista de comparecimento de uma Ação.
///
/// [attended] é `bool?` de propósito, e é o coração desta feature:
///   `null`  — não registrado. Ninguém disse nada ainda.
///   `false` — ausente, e só depois de a lista ser fechada.
///   `true`  — presente.
///
/// Um `bool` simples colapsaria os dois primeiros, e o app passaria a acusar de
/// ausência quem apenas não foi marcado — que é o defeito que a change inteira
/// existe para impedir.
class AttendanceMark {
  const AttendanceMark({
    required this.profile,
    required this.attendedAt,
    required this.disputed,
  });

  final PublicProfile profile;

  /// Instante da marca, ou `null` se ninguém marcou.
  final DateTime? attendedAt;

  /// Se alguém já contestou esta linha. Uma vez `true`, nunca volta a `false`.
  final bool disputed;

  bool get isMarked => attendedAt != null;
}

/// O estado da lista de uma Ação: aberta, ou fechada com a contagem congelada.
class AttendanceList {
  const AttendanceList({
    required this.marks,
    required this.closedAt,
    required this.presentAtClosing,
  });

  final List<AttendanceMark> marks;
  final DateTime? closedAt;

  /// Quantas pessoas constavam como presentes no momento do fechamento.
  ///
  /// Fato datado, não consulta: sobrevive à faxina que apaga as linhas
  /// nominais dois anos depois.
  final int? presentAtClosing;

  bool get isClosed => closedAt != null;

  /// Quem tem marca, agora.
  int get presentCount => marks.where((mark) => mark.isMarked).length;
}

/// Uma presença registrada SOBRE a pessoa que está olhando.
///
/// Existe separada de [AttendanceMark] porque a pergunta é outra: lá é "quem
/// esteve nesta Ação", aqui é "o que disseram sobre mim, e onde".
class MyAttendanceRecord {
  const MyAttendanceRecord({
    required this.actionId,
    required this.actionName,
    required this.actionDate,
    required this.attendedAt,
    required this.markedByName,
    required this.dispute,
  });

  final String actionId;

  /// Nome da Ação, ou um substituto quando ela não é mais legível.
  final String actionName;

  /// `null` quando a Ação deixou de ser legível para esta pessoa — Ação
  /// restrita de um Grupo do qual ela saiu.
  ///
  /// A marca sobre ela continua existindo e continua contestável; o que se
  /// perde é o contexto, não o direito. Achado C-2 da convergência 1.
  final DateTime? actionDate;

  final DateTime attendedAt;

  /// Nome de quem afirmou. Nunca o id: quem lê precisa saber QUEM disse.
  final String markedByName;

  /// A contestação, se já houver uma.
  final AttendanceDispute? dispute;

  bool get canDispute => dispute == null;
}

/// A contestação e o que aconteceu com ela.
class AttendanceDispute {
  const AttendanceDispute({
    required this.disputedAt,
    required this.decision,
  });

  final DateTime disputedAt;

  /// `mantida`, `desfeita`, ou `null` enquanto ninguém decidiu.
  ///
  /// Chave de banco, portanto em português — fronteira de idioma de
  /// `CONTEXT.md`.
  final String? decision;

  bool get isPending => decision == null;
}

/// Uma contestação esperando decisão de quem criou a Ação.
class PendingDispute {
  const PendingDispute({
    required this.actionId,
    required this.profile,
    required this.disputedAt,
  });

  final String actionId;
  final PublicProfile profile;
  final DateTime disputedAt;
}

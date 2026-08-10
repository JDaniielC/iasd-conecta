/// O estrago declarado antes de arquivar um Grupo (feature 014, FR-003).
///
/// Arquivar cancela Ações futuras e encerra Rodadas de votação. Quem decide
/// precisa ver o tamanho disso **antes** de confirmar — não descobrir depois
/// que cancelou um encontro para o qual doze pessoas já tinham dito sim.
class ArchivePreview {
  const ArchivePreview({
    required this.futureActions,
    required this.confirmedAttendances,
    required this.openVotingRounds,
    required this.members,
  });

  /// Ações confirmadas do Grupo que ainda vão acontecer. Só estas são
  /// canceladas — Ação passada é histórico e não é tocada.
  final int futureActions;

  /// Quantas presenças estavam confirmadas nessas Ações futuras. É o número
  /// que transforma "2 Ações" em "12 pessoas esperando".
  final int confirmedAttendances;

  final int openVotingRounds;
  final int members;

  /// Quando nada será perdido, a tela diz isso **em palavras** — quatro zeros
  /// obrigam a pessoa a interpretar, e interpretar antes de uma ação
  /// irreversível é onde o erro acontece (FR-004).
  bool get nothingWillBeLost =>
      futureActions == 0 && confirmedAttendances == 0 && openVotingRounds == 0;
}

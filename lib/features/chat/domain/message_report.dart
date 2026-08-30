/// Em que pé está a denúncia. Chave em português no banco, identificador em
/// inglês no Dart — fronteira de idioma do `CONTEXT.md`.
enum MessageReportState {
  pending('pendente'),
  messageRemoved('mensagem_removida'),
  dismissed('improcedente'),

  /// A mensagem sumiu antes de alguém decidir — expurgo dos 30 dias. Não é
  /// desfecho de mérito, e por isso é um estado próprio: dizer "improcedente"
  /// sobre um caso que ninguém julgou seria registrar uma decisão que não
  /// houve.
  noMessage('sem_mensagem');

  const MessageReportState(this.key);

  final String key;

  static MessageReportState? fromKey(String key) {
    for (final s in MessageReportState.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// Uma linha de `public.denuncias_mensagem`.
///
/// [reason] é o que quem denunciou escreveu, e é o ÚNICO registro do caso: o
/// texto denunciado não é conservado em lugar nenhum. Quem analisa lê a
/// mensagem enquanto ela existe e o motivo depois — se remover primeiro, sobra
/// só o motivo.
///
/// **[reason] é nulo depois do prazo** (change `denuncia-como-registro`):
/// `denuncia_prazo_do_motivo()`, contado do desfecho, apaga o texto — nunca o
/// registro. Uma denúncia PENDENTE nunca tem [reason] nulo; só quem já tem
/// [state] resolvido pode ter perdido o motivo.
class MessageReport {
  const MessageReport({
    required this.id,
    required this.reason,
    required this.state,
    required this.createdAt,
    this.messageId,
    this.messageText,
    this.messageRemoved = false,
  });

  final String id;
  final String? reason;
  final MessageReportState state;
  final DateTime createdAt;

  /// Nulo depois do expurgo — `on delete set null`, não cascade. Denúncia
  /// pendente que some sem desfecho é o pior resultado para quem denunciou.
  final String? messageId;

  /// Nulo quando a mensagem já foi removida ou o autor excluiu a conta.
  final String? messageText;
  final bool messageRemoved;

  static MessageReport? fromMap(Map<String, dynamic> map) {
    final state = MessageReportState.fromKey(map['estado'] as String);
    // Estado que este build não conhece é IGNORADO, não derruba a lista —
    // mesma escolha de `NotificationType.fromKey`. A migration vai antes do
    // build web, então por alguns minutos o banco pode ter um estado que o app
    // ainda não sabe desenhar.
    if (state == null) return null;

    // Colunas PLANAS, vindas de `denuncias_do_espaco`. A versão anterior lia um
    // objeto embutido `mensagens` do PostgREST, e o embed com `!inner` era
    // justamente o que escondia do Dono do Grupo as denúncias dos chats das
    // Ações dele. `fetchOrphanReports` lê a tabela direto e não traz estas duas
    // — denúncia órfã não tem mensagem —, então ambas são opcionais.
    return MessageReport(
      id: map['id'] as String,
      reason: map['motivo'] as String?,
      state: state,
      createdAt: DateTime.parse(map['created_at'] as String),
      messageId: map['mensagem_id'] as String?,
      messageText: map['mensagem_texto'] as String?,
      messageRemoved: map['mensagem_removida_em'] != null,
    );
  }
}

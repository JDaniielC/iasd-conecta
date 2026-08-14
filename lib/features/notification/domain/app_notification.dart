/// O que provocou o aviso. Chave em português no banco, identificador em inglês
/// no Dart — fronteira de idioma do `CONTEXT.md`.
enum NotificationType {
  inviteReceived('convite_recebido'),
  inviteAccepted('convite_aceito'),
  inviteDeclined('convite_recusado');

  const NotificationType(this.key);

  final String key;

  /// `null` para tipo que este build não conhece.
  ///
  /// A tabela nasceu genérica de propósito — chat e log de mudanças entram como
  /// tipos novos depois. A migration vai antes do build web, então por alguns
  /// minutos o banco pode ter um tipo que o app ainda não sabe desenhar. Uma
  /// linha desconhecida é IGNORADA; derrubar a lista inteira por causa dela
  /// seria trocar um aviso que falta por nenhum aviso.
  static NotificationType? fromKey(String key) {
    for (final t in NotificationType.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Uma linha de `public.notificacoes`.
///
/// O aviso de aceite NÃO guarda se a pessoa entrou como confirmada ou em fila:
/// quem estava na fila é promovido depois, e um status congelado passaria a
/// mentir. Quem quiser o estado de agora lê `confirmacoes_acao`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.actorName,
    this.actionId,
    this.actionName,
    this.groupName,
    this.readAt,
  });

  final String id;
  final NotificationType type;
  final DateTime createdAt;

  /// Resolvido na leitura, por `perfil_publico`.
  final String? actorName;
  final String? actionId;
  final String? actionName;
  final String? groupName;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  static AppNotification? fromMap(
    Map<String, dynamic> map, {
    String? actorName,
    String? groupName,
  }) {
    final type = NotificationType.fromKey(map['tipo'] as String);
    if (type == null) return null;
    return AppNotification(
      id: map['id'] as String,
      type: type,
      createdAt: DateTime.parse(map['created_at'] as String),
      actorName: actorName,
      actionId: map['acao_id'] as String?,
      actionName: map['acao_nome'] as String?,
      groupName: groupName,
      readAt: map['lida_em'] == null
          ? null
          : DateTime.parse(map['lida_em'] as String),
    );
  }

  /// A frase da tela: quem, o quê, e por qual Grupo.
  ///
  /// Sem autor a frase sai sem sujeito — "Alguém aceitou" —, e não com o nome
  /// removido, que não seria frase.
  String get sentence {
    final quem = actorName ?? 'Alguém';
    final onde = groupName == null ? '' : ' — pelo Grupo $groupName';
    return switch (type) {
      NotificationType.inviteReceived => '$quem convidou você$onde',
      NotificationType.inviteAccepted => '$quem aceitou seu convite$onde',
      NotificationType.inviteDeclined => '$quem recusou seu convite$onde',
    };
  }
}

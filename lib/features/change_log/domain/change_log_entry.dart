/// O que aconteceu. As chaves são as do banco, em português; o identificador
/// Dart é em inglês — fronteira de idioma do `CONTEXT.md`.
enum ChangeLogType {
  actionCreated('acao_criada'),
  actionTimeChanged('acao_horario_alterado'),
  actionPlaceChanged('acao_local_alterado'),
  actionCancelled('acao_cancelada'),
  memberJoined('participacao_entrou'),
  memberLeft('participacao_saiu'),
  attendanceConfirmed('confirmacao_confirmado'),
  attendanceQueued('confirmacao_fila'),
  attendanceWithdrawn('confirmacao_cancelada'),
  groupArchived('grupo_arquivado');

  const ChangeLogType(this.key);

  /// O valor gravado em `mudancas.tipo`.
  final String key;

  /// `null` para tipo que este build não conhece.
  ///
  /// Acontece de verdade: a migration vai antes do build web, então por alguns
  /// minutos o banco pode ter um tipo que o app ainda não sabe desenhar. Uma
  /// linha desconhecida é **ignorada**, nunca derruba a lista — o histórico
  /// aparecer incompleto por um instante é melhor que a tela sumir.
  static ChangeLogType? fromKey(String key) {
    for (final t in ChangeLogType.values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// Uma linha de `public.mudancas`.
///
/// Não guarda valor anterior nem valor novo: o registro diz QUE mudou, não de
/// que para que. E não guarda o nome de quem fez — só a referência ao Perfil,
/// para a anonimização da exclusão de Conta propagar sozinha.
class ChangeLogEntry {
  const ChangeLogEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    this.groupId,
    this.actionId,
    this.authorId,
    this.authorName,
  });

  final String id;
  final ChangeLogType type;
  final DateTime createdAt;
  final String? groupId;
  final String? actionId;

  /// Anulável porque nem todo evento tem autor identificável no momento do
  /// gatilho — remoção em cascata não tem sessão. Onde é nulo, a frase da tela
  /// sai sem sujeito.
  final String? authorId;

  /// Resolvido na leitura via `perfil_publico`, nunca gravado junto.
  final String? authorName;

  /// `null` quando o `tipo` do banco não existe neste build.
  static ChangeLogEntry? fromMap(Map<String, dynamic> map, {String? authorName}) {
    final type = ChangeLogType.fromKey(map['tipo'] as String);
    if (type == null) return null;
    return ChangeLogEntry(
      id: map['id'] as String,
      type: type,
      createdAt: DateTime.parse(map['created_at'] as String),
      groupId: map['grupo_id'] as String?,
      actionId: map['acao_id'] as String?,
      authorId: map['autor_id'] as String?,
      authorName: authorName,
    );
  }

  /// A frase que a tela mostra.
  ///
  /// Dez tipos × dois casos (com autor e sem). A versão sem sujeito não é a
  /// mesma frase com o nome removido — "entrou no Grupo" sozinho não é frase;
  /// "alguém entrou no Grupo" é.
  String get sentence {
    final who = authorName;
    return switch (type) {
      ChangeLogType.actionCreated => who == null
          ? 'Uma Ação foi criada neste Grupo'
          : '$who criou uma Ação neste Grupo',
      ChangeLogType.actionTimeChanged =>
        who == null ? 'O horário da Ação mudou' : '$who mudou o horário da Ação',
      ChangeLogType.actionPlaceChanged =>
        who == null ? 'O local da Ação mudou' : '$who mudou o local da Ação',
      ChangeLogType.actionCancelled =>
        who == null ? 'A Ação foi cancelada' : '$who cancelou a Ação',
      ChangeLogType.memberJoined =>
        who == null ? 'Alguém entrou no Grupo' : '$who entrou no Grupo',
      ChangeLogType.memberLeft =>
        who == null ? 'Alguém saiu do Grupo' : '$who saiu do Grupo',
      ChangeLogType.attendanceConfirmed => who == null
          ? 'Alguém confirmou presença'
          : '$who confirmou presença',
      ChangeLogType.attendanceQueued =>
        who == null ? 'Alguém entrou na fila' : '$who entrou na fila',
      ChangeLogType.attendanceWithdrawn => who == null
          ? 'Alguém não vem mais'
          : '$who não vem mais',
      ChangeLogType.groupArchived =>
        who == null ? 'O Grupo foi arquivado' : '$who arquivou o Grupo',
    };
  }
}

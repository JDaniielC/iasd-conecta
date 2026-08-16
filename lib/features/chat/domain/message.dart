/// Por que a mensagem não tem texto. Derivado, nunca gravado.
///
/// A tabela `public.mensagens` não tem coluna de motivo, de propósito: as duas
/// colunas que já precisam existir — `texto` e `removida_em` — bastam para
/// distinguir os três estados, e uma terceira coluna seria informação
/// redundante que pode divergir das outras duas.
///
/// | `texto` | `removida_em` | estado |
/// |---|---|---|
/// | preenchido | nulo | [visible] |
/// | nulo | preenchido | [removedByModeration] |
/// | nulo | nulo | [authorDeletedAccount] |
///
/// A quarta combinação — texto preenchido COM `removida_em` — o banco não
/// produz: o gatilho `mensagens_so_remove` recusa `update` que deixe `texto`
/// não nulo. Se ela chegar mesmo assim, este código trata como removida e
/// esconde o texto. É a direção segura: mostrar conteúdo que alguém decidiu
/// remover é o erro que não dá para desfazer; esconder conteúdo que deveria
/// aparecer, dá.
enum MessageTombstone {
  /// Não é lápide — a mensagem está aí.
  visible,

  /// Removida por quem tem autoridade sobre o espaço, ou pelo próprio autor.
  removedByModeration,

  /// O autor excluiu a conta. O texto era dele e saiu com ele; a linha fica
  /// para a conversa continuar legível para quem ficou.
  authorDeletedAccount,
}

/// Uma linha de `public.mensagens`.
///
/// [text] é nulo nas duas lápides, e é por isso que a tela nunca deve exibi-lo
/// sem antes olhar [tombstone].
class Message {
  const Message({
    required this.id,
    required this.authorId,
    required this.createdAt,
    this.groupId,
    this.actionId,
    this.text,
    this.removedAt,
    this.authorName,
  });

  final String id;
  final String authorId;
  final DateTime createdAt;

  /// Exatamente um dos dois é não nulo — `mensagens_um_espaco_so` garante.
  final String? groupId;
  final String? actionId;

  final String? text;
  final DateTime? removedAt;

  /// Resolvido na leitura por `perfil_publico`, como em
  /// `NotificationRepository`. Nunca por `select` direto em `perfis`: é
  /// `perfil_publico` que devolve o Apelido no lugar do nome quando a pessoa é
  /// menor de idade.
  final String? authorName;

  MessageTombstone get tombstone {
    if (removedAt != null) return MessageTombstone.removedByModeration;
    if (text == null) return MessageTombstone.authorDeletedAccount;
    return MessageTombstone.visible;
  }

  static Message fromMap(Map<String, dynamic> map, {String? authorName}) {
    return Message(
      id: map['id'] as String,
      authorId: map['autor_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      groupId: map['grupo_id'] as String?,
      actionId: map['acao_id'] as String?,
      text: map['texto'] as String?,
      removedAt: map['removida_em'] == null
          ? null
          : DateTime.parse(map['removida_em'] as String),
      authorName: authorName,
    );
  }
}

/// Junta duas versões da mesma conversa, deduzindo por `id`.
///
/// A mesma mensagem chega pelos DOIS caminhos, e é assim de propósito: quem
/// escreve recebe o próprio `insert` de volta pelo canal, e quem reconecta
/// refaz a consulta sobre um período que o canal já cobriu. Sem dedução, a
/// conversa mostra a linha duas vezes — e o defeito só aparece com duas
/// pessoas falando, que é o cenário que ninguém testa à mão.
///
/// QUEM VENCE NÃO É QUEM CHEGA DEPOIS, e esta foi a lição cara desta change.
/// "Depois" é ordem de rede, e ela mente nos dois sentidos — as duas versões
/// foram medidas:
///
/// - a consulta inicial ainda em voo responde com a linha ANTERIOR à remoção
///   que o canal já entregou;
/// - a cópia de antes de o canal cair ganha da consulta que a reconexão
///   refez, e a remoção ocorrida durante a queda é descartada.
///
/// Nos dois casos o texto de uma mensagem removida volta para a tela, e a spec
/// de moderação diz que ele não volta para ninguém.
///
/// A regra que não depende de relógio nem de ordem de chegada: **a lápide é
/// ABSORVENTE**. Entre duas versões da mesma linha vence a que avançou mais em
/// [MessageTombstone] — visível, depois conta excluída, depois removida. É o
/// banco que garante que isso é sempre a versão mais nova:
/// `mensagens_so_remove` recusa qualquer `update` que deixe `texto` não nulo, e
/// preserva `removida_em` uma vez gravado. Texto não ressuscita, então a versão
/// com menos texto é sempre a de depois.
///
/// Empate de estado — a mesma linha pelos dois caminhos, sem mudança — fica com
/// [newer], que é o que traz o nome do autor já resolvido.
///
/// Ordem final é cronológica crescente — a conversa se lê de cima para baixo,
/// ao contrário da consulta, que pede as mais recentes primeiro para paginar.
List<Message> mergeMessages(Iterable<Message> older, Iterable<Message> newer) {
  final byId = <String, Message>{};
  for (final m in older) {
    byId[m.id] = m;
  }
  for (final m in newer) {
    final existing = byId[m.id];
    // `>` e não `>=`: no empate quem entra é [newer].
    if (existing != null && _tombstoneRank(existing) > _tombstoneRank(m)) {
      continue;
    }
    byId[m.id] = m;
  }
  final merged = byId.values.toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return merged;
}

/// Quanto a linha já avançou rumo a não ter mais texto. Monotônico por
/// construção do banco — ver [mergeMessages].
int _tombstoneRank(Message m) => switch (m.tombstone) {
  MessageTombstone.visible => 0,
  MessageTombstone.authorDeletedAccount => 1,
  MessageTombstone.removedByModeration => 2,
};

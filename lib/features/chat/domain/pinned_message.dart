/// Uma mensagem fixada, vista de FORA da conversa — em `Meu Perfil`.
///
/// Sem `pinnedBy`: quem fixou é dado sobre outra pessoa, e a função do banco
/// que alimenta esta classe (`minhas_mensagens_fixadas`) não devolve essa
/// coluna. Ver o `comment on function` na migration
/// `20260830100000_alcance_do_titular_sobre_texto_proprio.sql`.
class PinnedMessage {
  const PinnedMessage({
    required this.id,
    required this.text,
    required this.pinnedAt,
    required this.spaceName,
  });

  factory PinnedMessage.fromMap(Map<String, dynamic> map) {
    return PinnedMessage(
      id: map['id'] as String,
      text: map['texto'] as String,
      pinnedAt: DateTime.parse(map['fixada_em'] as String),
      spaceName: map['nome_espaco'] as String,
    );
  }

  final String id;
  final String text;
  final DateTime pinnedAt;

  /// Nome do Grupo/Ministério ou da Ação de onde a mensagem é — para a
  /// pessoa saber de onde é, já que ela pode não alcançar mais aquela
  /// conversa para descobrir sozinha.
  final String spaceName;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';

/// Change `chat-de-grupo-e-acao` — a mesma mensagem chega pelos DOIS caminhos.
///
/// Quem escreve recebe o próprio `insert` de volta pelo canal; quem reconecta
/// refaz a consulta sobre um período que o canal já cobriu. Sem dedução por
/// `id`, a conversa mostra a linha duas vezes — e o defeito só aparece com duas
/// pessoas falando ao mesmo tempo, que é o cenário que ninguém testa à mão.
///
/// O caso que mais importa é o da REMOÇÃO, e ele decidiu a regra. A primeira
/// versão era "quem chega depois vence", e ela quebra nos DOIS sentidos —
/// medido nas convergências 4 e 5: a consulta em voo responde com a linha
/// anterior à remoção que o canal já entregou, e a cópia de antes da queda
/// ganha da consulta que a reconexão refez. Nos dois casos o texto removido
/// volta para a tela.
///
/// A regra que vale é **a lápide é absorvente**: entre duas versões da mesma
/// linha vence a que avançou mais em `MessageTombstone`. É o banco que garante
/// que isso é sempre a versão mais nova — `mensagens_so_remove` recusa
/// qualquer `update` que deixe `texto` não nulo. Texto não ressuscita.

Message _message(
  String id, {
  String? text = 'oi',
  DateTime? removedAt,
  int minute = 0,
}) => Message(
  id: id,
  authorId: 'u1',
  createdAt: DateTime.utc(2026, 8, 14, 10, minute),
  groupId: 'g1',
  text: text,
  removedAt: removedAt,
);

void main() {
  test('a mesma mensagem pelos dois caminhos aparece UMA vez', () {
    final fromQuery = [_message('a'), _message('b', minute: 1)];
    final fromChannel = [_message('b', minute: 1)];

    final merged = mergeMessages(fromQuery, fromChannel);

    expect(merged.map((m) => m.id), ['a', 'b']);
  });

  test('nada se perde: o que só existe num dos caminhos continua lá', () {
    final fromQuery = [_message('a'), _message('b', minute: 1)];
    final fromChannel = [_message('c', minute: 2)];

    final merged = mergeMessages(fromQuery, fromChannel);

    expect(merged.map((m) => m.id), ['a', 'b', 'c']);
  });

  test('a remoção vence o histórico que ainda tinha o texto', () {
    final fromQuery = [_message('a', text: 'algo que saiu')];
    final removal = [
      _message('a', text: null, removedAt: DateTime.utc(2026, 8, 14, 11)),
    ];

    final merged = mergeMessages(fromQuery, removal);

    expect(merged, hasLength(1));
    expect(merged.single.tombstone, MessageTombstone.removedByModeration);
    expect(merged.single.text, isNull);
  });

  test('e vence NA ORDEM INVERSA também — é o que "absorvente" quer dizer', () {
    // Este é o caso que "quem chega depois vence" perdia, e ele não é
    // hipotético: é a consulta da reconexão trazendo a remoção ocorrida durante
    // a queda, contra a cópia que estava na tela desde antes. Medido na
    // convergência 5.
    final removal = [
      _message('a', text: null, removedAt: DateTime.utc(2026, 8, 14, 11)),
    ];
    final staleCopy = [_message('a', text: 'algo que saiu')];

    final merged = mergeMessages(removal, staleCopy);

    expect(merged.single.text, isNull);
    expect(merged.single.tombstone, MessageTombstone.removedByModeration);
  });

  test('conta excluída também não volta a ter texto', () {
    // A outra lápide. Ela é intermediária: uma mensagem de conta excluída ainda
    // pode ser removida por moderação depois, e por isso vale menos que a
    // remoção — mas mais que o texto.
    final deletedAccount = [_message('a', text: null)];
    final staleCopy = [_message('a', text: 'o que a pessoa escreveu')];

    expect(mergeMessages(deletedAccount, staleCopy).single.text, isNull);
    expect(
      mergeMessages(deletedAccount, staleCopy).single.tombstone,
      MessageTombstone.authorDeletedAccount,
    );
  });

  test('a ordem final é cronológica crescente, não a da consulta', () {
    // A consulta pede as mais recentes primeiro, para paginar. A conversa se lê
    // de cima para baixo. A inversão mora aqui, uma vez, e não em cada tela.
    final fromQuery = [
      _message('c', minute: 2),
      _message('b', minute: 1),
      _message('a'),
    ];

    final merged = mergeMessages(fromQuery, const []);

    expect(merged.map((m) => m.id), ['a', 'b', 'c']);
  });

  test('juntar com vazio dos dois lados não inventa nem perde', () {
    expect(mergeMessages(const [], const []), isEmpty);
    expect(mergeMessages([_message('a')], const []).single.id, 'a');
    expect(mergeMessages(const [], [_message('a')]).single.id, 'a');
  });
}

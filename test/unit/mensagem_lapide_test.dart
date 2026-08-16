import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';

/// Change `chat-de-grupo-e-acao` — as três lápides, derivadas de duas colunas.
///
/// A tabela não tem coluna de motivo, de propósito: `texto` e `removida_em` já
/// precisam existir e já bastam. Uma terceira coluna seria informação
/// redundante que pode divergir das outras duas — e quando divergir, a tela
/// escreve o motivo errado sobre um fato certo.
///
/// Seis casos: `texto` em três estados (preenchido, vazio, nulo) × `removida_em`
/// em dois. Dois deles o banco não produz — `mensagens_texto_no_limite` recusa
/// texto vazio, e `mensagens_so_remove` recusa `update` que deixe texto não
/// nulo. Estão aqui porque o modelo precisa decidir alguma coisa se chegarem, e
/// "alguma coisa" precisa ser escolhida em vez de acontecer.

Message _message({String? text, DateTime? removedAt}) => Message(
  id: 'm1',
  authorId: 'u1',
  createdAt: DateTime.utc(2026, 8, 14),
  groupId: 'g1',
  text: text,
  removedAt: removedAt,
);

void main() {
  final removedAt = DateTime.utc(2026, 8, 14, 10);

  group('sem removida_em', () {
    test('texto preenchido é a mensagem', () {
      expect(
        _message(text: 'quem leva o som?').tombstone,
        MessageTombstone.visible,
      );
    });

    test('texto nulo é lápide de conta excluída', () {
      expect(_message().tombstone, MessageTombstone.authorDeletedAccount);
    });

    test('texto vazio conta como texto — o banco é quem recusa vazio', () {
      // A constraint é a autoridade sobre o que entra. Se uma string vazia
      // chegar aqui, ela veio de uma linha que o banco aceitou, e inventar uma
      // lápide para ela seria o cliente dizer "conta excluída" sobre alguém que
      // não excluiu nada.
      expect(_message(text: '').tombstone, MessageTombstone.visible);
    });
  });

  group('com removida_em', () {
    test('texto nulo é lápide de moderação', () {
      expect(
        _message(removedAt: removedAt).tombstone,
        MessageTombstone.removedByModeration,
      );
    });

    test('texto preenchido AINDA é remoção — a remoção vence', () {
      // O banco não produz esta combinação. Se produzir, esconder o texto é a
      // direção segura: mostrar conteúdo que alguém decidiu remover é o erro
      // que não dá para desfazer.
      expect(
        _message(text: 'algo', removedAt: removedAt).tombstone,
        MessageTombstone.removedByModeration,
      );
    });

    test('texto vazio com remoção também é remoção', () {
      expect(
        _message(text: '', removedAt: removedAt).tombstone,
        MessageTombstone.removedByModeration,
      );
    });
  });

  test('fromMap lê as colunas do banco, que continuam em português', () {
    final m = Message.fromMap({
      'id': 'm9',
      'autor_id': 'u9',
      'created_at': '2026-08-14T12:00:00.000Z',
      'grupo_id': 'g9',
      'acao_id': null,
      'texto': 'oi',
      'removida_em': null,
    }, authorName: 'Fulana');

    expect(m.id, 'm9');
    expect(m.authorId, 'u9');
    expect(m.groupId, 'g9');
    expect(m.actionId, isNull);
    expect(m.text, 'oi');
    expect(m.authorName, 'Fulana');
    expect(m.tombstone, MessageTombstone.visible);
  });
}

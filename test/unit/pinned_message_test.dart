import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/domain/pinned_message.dart';

/// Change `alcance-do-titular-sobre-texto-proprio` — `PinnedMessage.fromMap`
/// lê o retorno de `minhas_mensagens_fixadas()`.
void main() {
  test('fromMap lê texto, instante e nome do espaço', () {
    final message = PinnedMessage.fromMap({
      'id': 'm1',
      'texto': 'o ponto de encontro mudou',
      'fixada_em': '2026-08-16T12:00:00.000Z',
      'grupo_id': 'g1',
      'acao_id': null,
      'nome_espaco': 'Grupo de Jovens',
    });

    expect(message.id, 'm1');
    expect(message.text, 'o ponto de encontro mudou');
    expect(message.pinnedAt, DateTime.utc(2026, 8, 16, 12, 0));
    expect(message.spaceName, 'Grupo de Jovens');
  });

  test('não tem fixada_por — a função do banco não devolve essa coluna', () {
    // Regressão: a classe não tem o campo, então nem compila se alguém
    // tentar ler `map['fixada_por']` aqui. O teste documenta a garantia.
    final message = PinnedMessage.fromMap({
      'id': 'm2',
      'texto': 'oi',
      'fixada_em': '2026-08-16T12:00:00.000Z',
      'grupo_id': null,
      'acao_id': 'a1',
      'nome_espaco': 'Reunião de Sábado',
    });

    expect(message, isNot(isNull));
  });
}

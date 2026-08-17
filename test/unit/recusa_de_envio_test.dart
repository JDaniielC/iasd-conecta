import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal_message.dart';

/// Change `filtro-e-intervalo-de-mensagem` — a tradução de código de erro para
/// frase, sem banco e sem tela.
///
/// A ponta de cima (o PostgREST devolve mesmo `PT422`/`PT425`/`PT429` com o
/// `hint`) é provada em `test/integration/limites_de_chat_test.dart`, contra o
/// servidor de verdade. A ponta de baixo (a tela desenha as três diferente) é
/// provada em `test/widget/conversa_recusa_test.dart`. O que sobra para aqui é
/// o meio: os casos de borda que nem um nem outro alcança sem esforço.
void main() {
  group('o código decide, e só ele', () {
    test('os três códigos viram as três causas', () {
      expect(
        SendRefusal.fromCode('PT422', 'xatoxo')!.kind,
        SendRefusalKind.blockedWord,
      );
      expect(
        SendRefusal.fromCode('PT425', '3')!.kind,
        SendRefusalKind.tooSoon,
      );
      expect(
        SendRefusal.fromCode('PT429', '90')!.kind,
        SendRefusalKind.windowCeiling,
      );
    });

    test('qualquer outro código não é recusa de escrita', () {
      // Sem este caso, um `fromCode` que devolvesse sempre `blockedWord`
      // passaria no de cima — e a tela explicaria palavra bloqueada para uma
      // violação de chave única.
      for (final code in ['23505', '42501', 'PGRST301', '', null]) {
        expect(SendRefusal.fromCode(code, 'x'), isNull, reason: '$code');
      }
    });

    test('a palavra e os segundos saem do hint', () {
      expect(SendRefusal.fromCode('PT422', 'xatoxo')!.blockedWord, 'xatoxo');
      expect(
        SendRefusal.fromCode('PT425', '3')!.retryAfter,
        const Duration(seconds: 3),
      );
    });

    test('hint ausente ou ilegível não derruba a recusa', () {
      // Um proxy que corte o `hint` não pode transformar uma recusa explicável
      // numa exceção crua: a causa ainda é conhecida, só o detalhe some.
      expect(SendRefusal.fromCode('PT422', null)!.blockedWord, isNull);
      expect(SendRefusal.fromCode('PT425', 'não é número')!.retryAfter, isNull);
      expect(
        SendRefusal.fromCode('PT425', null)!.kind,
        SendRefusalKind.tooSoon,
      );
    });
  });

  group('a frase', () {
    test('a de palavra nomeia a palavra, e a sem palavra ainda orienta', () {
      const named = SendRefusal(
        kind: SendRefusalKind.blockedWord,
        blockedWord: 'xatoxo',
      );
      expect(sendRefusalMessage(named), contains('xatoxo'));

      const anonymous = SendRefusal(kind: SendRefusalKind.blockedWord);
      final fallback = sendRefusalMessage(anonymous);
      expect(fallback, contains('Reveja o texto'));
      expect(fallback, isNot(contains('null')));
    });

    test('intervalo e teto nunca dizem a mesma coisa', () {
      const tooSoon = SendRefusal(
        kind: SendRefusalKind.tooSoon,
        retryAfter: Duration(seconds: 3),
      );
      const ceiling = SendRefusal(
        kind: SendRefusalKind.windowCeiling,
        retryAfter: Duration(seconds: 3),
      );
      expect(
        sendRefusalMessage(tooSoon, remaining: const Duration(seconds: 3)),
        isNot(
          sendRefusalMessage(ceiling, remaining: const Duration(seconds: 3)),
        ),
        reason:
            'mesmo com o MESMO tempo restante: a pessoa precisa saber se espera '
            'três segundos ou se parou de falar por um tempo',
      );
    });

    test('a contagem arredonda para CIMA e nunca chega a zero', () {
      // Truncar é o defeito silencioso: o relógio da tela roda alguns
      // milissegundos depois da resposta do servidor, e "0 segundos" com o
      // envio ainda fechado é a tela desmentindo a si mesma.
      const refusal = SendRefusal(kind: SendRefusalKind.tooSoon);
      expect(
        sendRefusalMessage(refusal, remaining: const Duration(milliseconds: 2900)),
        contains('3 segundos'),
      );
      expect(
        sendRefusalMessage(refusal, remaining: const Duration(milliseconds: 1)),
        contains('1 segundo'),
      );
      expect(
        sendRefusalMessage(refusal, remaining: Duration.zero),
        contains('um instante'),
      );
    });

    test('minuto no singular e no plural, e nunca "119 segundos"', () {
      const refusal = SendRefusal(kind: SendRefusalKind.windowCeiling);
      expect(
        sendRefusalMessage(refusal, remaining: const Duration(seconds: 60)),
        contains('1 minuto'),
      );
      expect(
        sendRefusalMessage(refusal, remaining: const Duration(seconds: 119)),
        contains('2 minutos'),
      );
      expect(
        sendRefusalMessage(refusal, remaining: const Duration(seconds: 59)),
        contains('59 segundos'),
      );
    });

    test('sem tempo restante a frase ainda serve', () {
      // `retryAfter` nulo acontece quando o `hint` não chegou. A tela não pode
      // ficar muda por causa disso.
      for (final kind in SendRefusalKind.values) {
        final message = sendRefusalMessage(SendRefusal(kind: kind));
        expect(message, isNotEmpty, reason: '$kind');
        expect(message, isNot(contains('null')), reason: '$kind');
      }
    });
  });
}

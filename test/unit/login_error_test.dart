import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/profile/domain/login_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('FR-014: senha errada e e-mail inexistente dão a MESMA frase', () {
    // O Supabase devolve `invalid_credentials` para os dois casos — este
    // teste garante que a tela também não os separe. Separar é enumeração de
    // usuário: revelaria quem tem conta no app, e no app de um distrito
    // adventista isso é filiação religiosa (LGPD art. 5º, II).
    const senhaErrada = AuthApiException(
      'Invalid login credentials',
      statusCode: '400',
      code: 'invalid_credentials',
    );
    const emailInexistente = AuthApiException(
      'Invalid login credentials',
      statusCode: '400',
      code: 'invalid_credentials',
    );

    expect(loginErrorMessage(senhaErrada), loginErrorMessage(emailInexistente));
    expect(loginErrorMessage(senhaErrada), contains('E-mail ou senha'));
  });

  test('falha de rede não é tratada como senha errada', () {
    final semRede = AuthRetryableFetchException();
    final frase = loginErrorMessage(semRede);

    expect(frase, contains('internet'));
    // O erro de 2026-08-12: a tela dizia "Credenciais inválidas" (ou não
    // dizia nada) e mandava a pessoa reconferir uma senha que estava certa.
    expect(frase, isNot(contains('senha')));
  });

  test('e-mail não confirmado diz o que fazer', () {
    const naoConfirmado = AuthApiException(
      'Email not confirmed',
      statusCode: '400',
      code: 'email_not_confirmed',
    );

    expect(loginErrorMessage(naoConfirmado), contains('Confirme seu e-mail'));
  });

  test('limite de tentativas diz para esperar', () {
    const demais = AuthApiException(
      'Request rate limit reached',
      statusCode: '429',
      code: 'over_request_rate_limit',
    );

    expect(loginErrorMessage(demais), contains('Espere um pouco'));
  });

  test('erro de servidor não vira acusação à pessoa', () {
    const servidorFora = AuthApiException(
      'Internal Server Error',
      statusCode: '500',
    );
    final frase = loginErrorMessage(servidorFora);

    expect(frase, contains('serviço'));
    expect(frase, isNot(contains('senha')));
  });

  test('erro que não é de auth nenhum ainda produz uma frase', () {
    // O caminho que antes subia sem ninguém capturar e deixava a tela muda.
    final frase = loginErrorMessage(StateError('qualquer coisa'));

    expect(frase, isNotEmpty);
    expect(frase, isNot(contains('senha')));
  });
}

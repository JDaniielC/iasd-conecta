import 'package:supabase_flutter/supabase_flutter.dart';

/// A frase que a tela de login mostra para [error].
///
/// **A regra que não pode ser quebrada aqui (FR-014):** senha errada e e-mail
/// que nunca existiu devolvem a MESMA frase. Separá-las é enumeração de
/// usuário — qualquer pessoa testaria e-mails no formulário público e
/// descobriria quem tem conta. Num app de igreja isso revela filiação
/// religiosa, que a LGPD trata como dado sensível (art. 5º, II), e a base
/// inclui menor de idade. O Supabase já não distingue os dois (devolve
/// `invalid_credentials` para ambos) e
/// `test/integration/login_erro_generico_test.dart` trava esse contrato.
///
/// O que esta função existe para consertar é outra coisa: antes dela a tela
/// tratava **toda** falha como credencial inválida, e as que não são
/// `AuthException` — sem internet, servidor fora — subiam sem ninguém
/// capturar. O botão voltava ao normal e a tela não dizia nada. Ficar sem
/// resposta nenhuma é pior do que uma frase genérica: a pessoa reconfere uma
/// senha que estava certa o tempo todo.
String loginErrorMessage(Object error) {
  const credential = 'E-mail ou senha não conferem. Confira os dois e tente de novo.';

  if (error is AuthRetryableFetchException) {
    return 'Não deu pra falar com o serviço. Confira sua internet e tente de novo.';
  }

  if (error is AuthApiException) {
    final status = int.tryParse(error.statusCode ?? '');
    if (error.code == 'email_not_confirmed') {
      return 'Confirme seu e-mail antes de entrar. A mensagem de confirmação '
          'foi enviada para o endereço que você cadastrou.';
    }
    if (status == 429 ||
        error.code == 'over_request_rate_limit' ||
        error.code == 'over_email_send_rate_limit') {
      return 'Muitas tentativas seguidas. Espere um pouco antes de tentar de novo.';
    }
    if (status != null && status >= 500) {
      return 'O serviço não respondeu agora. Tente de novo em instantes.';
    }
    if (error.code == 'invalid_credentials') return credential;
  }

  // Sobrou o que não sabemos nomear. Não chute "senha errada": mandar a
  // pessoa reconferir uma senha correta por causa de um erro de rede é
  // exatamente o que esta função existe para evitar.
  if (error is AuthException) {
    return 'Não deu pra entrar agora. Tente de novo em instantes.';
  }
  return 'Não deu pra entrar agora. Tente de novo em instantes.';
}

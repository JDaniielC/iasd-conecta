/// Por que o banco recusou a escrita.
enum SendRefusalKind {
  /// O texto tem palavra da lista de conversa.
  blockedWord,

  /// Não decorreu o intervalo mínimo desde a última mensagem no mesmo chat.
  tooSoon,

  /// O teto de mensagens na janela foi atingido.
  windowCeiling,
}

/// A recusa que a tela sabe explicar.
///
/// **A CAUSA VEM DO CÓDIGO DO ERRO, NUNCA DO TEXTO DELE.** Interpretar a
/// mensagem do servidor é o que este arquivo existe para não fazer: texto se
/// reescreve, se traduz e ganha maiúscula sem ninguém notar, e no dia em que
/// isso acontecer a tela para de distinguir as três recusas — em silêncio, com
/// os testes verdes, porque nenhum deles olha o texto.
///
/// `profile_error_message.dart` faz o contrário e casa por `error.message`. Não
/// é descuido lá: aquelas recusas vêm de `check constraint`, e o único sinal que
/// um `check` violado carrega é o NOME da constraint, dentro do texto. Aqui as
/// recusas vêm de gatilho, que pode escolher o `errcode` — e escolhe.
///
/// Os três códigos são da família `PT`, que o PostgREST traduz para o código
/// HTTP dos três últimos dígitos. Um SQLSTATE inventado fora dela chegaria com o
/// código certo no corpo, mas como HTTP 500 — e recusa esperada subindo como
/// erro de servidor envenena log e alarme de produção.
class SendRefusal implements Exception {
  const SendRefusal({required this.kind, this.blockedWord, this.retryAfter});

  final SendRefusalKind kind;

  /// A palavra que causou a recusa, quando [kind] é
  /// [SendRefusalKind.blockedWord].
  ///
  /// É a palavra que a própria pessoa acabou de digitar — devolvê-la não vaza a
  /// lista, e não devolver nada produz uma recusa que ela não sabe corrigir.
  final String? blockedWord;

  /// Quanto falta para poder enviar, quando a recusa é de ritmo.
  final Duration? retryAfter;

  /// Lê a recusa do par (`code`, `hint`) que o servidor devolveu, ou `null`
  /// quando o erro é outro — falta de rede, policy, constraint.
  ///
  /// **Recebe os dois campos soltos, e não a exceção.** Este arquivo é Dart
  /// puro de propósito: a exceção do Supabase arrasta `package:supabase_flutter`
  /// e com ele o Flutter inteiro, e a prova de que o código sobrevive ao
  /// PostgREST roda em `dart test`, fora do Flutter. Quem desembrulha a exceção
  /// é `ChatRepository`, que já vive do lado do cliente.
  ///
  /// `hint` e não `message`: é o campo que o gatilho usa para o dado de máquina
  /// — a palavra num caso, os segundos que faltam nos outros dois.
  static SendRefusal? fromCode(String? code, String? hint) {
    switch (code) {
      case 'PT422':
        return SendRefusal(
          kind: SendRefusalKind.blockedWord,
          blockedWord: hint,
        );
      case 'PT425':
        return SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: _seconds(hint),
        );
      case 'PT429':
        return SendRefusal(
          kind: SendRefusalKind.windowCeiling,
          retryAfter: _seconds(hint),
        );
      default:
        return null;
    }
  }

  /// Segundos que faltam. Nulo quando o `hint` não veio ou não é número — a
  /// tela ainda consegue dizer QUE a recusa foi de ritmo, só não quanto falta.
  static Duration? _seconds(String? hint) {
    final value = int.tryParse(hint ?? '');
    return value == null ? null : Duration(seconds: value);
  }
}

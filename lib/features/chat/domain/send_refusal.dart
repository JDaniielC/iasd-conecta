/// Por que o banco recusou a escrita.
enum SendRefusalKind {
  /// O texto tem palavra da lista de conversa.
  blockedWord,

  /// Não decorreu o intervalo mínimo desde a última mensagem no mesmo chat.
  tooSoon,

  /// O teto de mensagens na janela foi atingido.
  windowCeiling,

  /// O chat já tem o número máximo de mensagens FIXADAS.
  ///
  /// Não é recusa de envio, e mora aqui mesmo assim: é a mesma disciplina —
  /// causa lida do `errcode`, dado de máquina no `hint` — e um segundo arquivo
  /// para decodificar um código da mesma família seria a cópia que diverge.
  pinnedCeiling,

  /// Já existe denúncia PENDENTE da mesma pessoa sobre a mesma mensagem
  /// (change `denuncia-como-registro`). Não é recusa de envio nem de fixação,
  /// e mora aqui pelo mesmo motivo de [pinnedCeiling]: mesma família de
  /// código, mesma disciplina de leitura.
  alreadyPending,
}

/// A recusa que a tela sabe explicar.
///
/// **A CAUSA VEM DO CÓDIGO DO ERRO, NUNCA DO TEXTO DELE.** Interpretar a
/// mensagem do servidor é o que este arquivo existe para não fazer: texto se
/// reescreve, se traduz e ganha maiúscula sem ninguém notar, e no dia em que
/// isso acontecer a tela para de distinguir as recusas — em silêncio, com os
/// testes verdes, porque nenhum deles olha o texto.
///
/// `profile_error_message.dart` faz o contrário e casa por `error.message`. Não
/// é descuido lá: aquelas recusas vêm de `check constraint`, e o único sinal que
/// um `check` violado carrega é o NOME da constraint, dentro do texto. Aqui as
/// recusas vêm de gatilho, que pode escolher o `errcode` — e escolhe.
///
/// Os códigos são da família `PT`, que o PostgREST traduz para o código
/// HTTP dos três últimos dígitos. Um SQLSTATE inventado fora dela chegaria com o
/// código certo no corpo, mas como HTTP 500 — e recusa esperada subindo como
/// erro de servidor envenena log e alarme de produção.
class SendRefusal implements Exception {
  const SendRefusal({
    required this.kind,
    this.blockedWord,
    this.retryAfter,
    this.ceiling,
  });

  final SendRefusalKind kind;

  /// A palavra que causou a recusa, quando [kind] é
  /// [SendRefusalKind.blockedWord].
  ///
  /// É a palavra que a própria pessoa acabou de digitar — devolvê-la não vaza a
  /// lista, e não devolver nada produz uma recusa que ela não sabe corrigir.
  final String? blockedWord;

  /// Quanto falta para poder enviar, quando a recusa é de ritmo.
  final Duration? retryAfter;

  /// Quantas fixadas cabem, quando [kind] é [SendRefusalKind.pinnedCeiling].
  /// Vem do `hint`, que é o banco dizendo o próprio teto — a tela não precisa
  /// confiar na cópia dela para escrever a frase.
  final int? ceiling;

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
      case 'PT409':
        return SendRefusal(
          kind: SendRefusalKind.pinnedCeiling,
          ceiling: int.tryParse(hint ?? ''),
        );
      case 'PT423':
        return const SendRefusal(kind: SendRefusalKind.alreadyPending);
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

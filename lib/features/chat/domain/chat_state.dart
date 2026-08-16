import 'message.dart';

/// Como está o canal de tempo real, para a tela poder DIZER.
///
/// Sem isto a queda do canal é indistinguível de "ninguém falou nada" — a tela
/// fica parada, correta e mentindo por omissão. A pessoa precisa saber se está
/// vendo a conversa de agora ou a de quando abriu.
enum ChatConnection {
  /// Canal assinado. O que aparecer chega sozinho.
  live,

  /// Caiu e está tentando voltar. O histórico continua legível.
  reconnecting,

  /// Sem tempo real nesta sessão. O chat FUNCIONA — só não sobe sozinho.
  offline,
}

/// O que a tela de conversa precisa saber, junto.
///
/// [messages] já vem COMPOSTA — histórico, páginas anteriores, o que o canal
/// entregou e o que a pessoa acabou de escrever, tudo resolvido por uma regra
/// só, dentro do `ChatNotifier`. A tela não junta nada.
///
/// Isto é a costura que faltava. Antes a lista se compunha em quatro lugares —
/// duas vezes no provider e duas no widget —, cada um decidindo por conta
/// própria quem vence, e a convergência 5 mediu três caminhos em que a cópia
/// local ganhava do servidor. Dois deles devolviam à tela o texto de uma
/// mensagem removida.
class ChatState {
  const ChatState({
    required this.messages,
    required this.connection,
    this.hasMoreOlder = true,
    this.loadingOlder = false,
  });

  /// A conversa inteira, em ordem cronológica crescente.
  final List<Message> messages;

  final ChatConnection connection;

  /// Ainda vale oferecer "carregar o que veio antes"? Falso quando uma página
  /// voltou vazia — sem isso o botão fica para sempre e cada toque é uma ida ao
  /// servidor que não traz nada.
  final bool hasMoreOlder;

  final bool loadingOlder;

  ChatState copyWith({
    List<Message>? messages,
    ChatConnection? connection,
    bool? hasMoreOlder,
    bool? loadingOlder,
  }) => ChatState(
    messages: messages ?? this.messages,
    connection: connection ?? this.connection,
    hasMoreOlder: hasMoreOlder ?? this.hasMoreOlder,
    loadingOlder: loadingOlder ?? this.loadingOlder,
  );
}

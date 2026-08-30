import 'send_refusal.dart';

/// A frase que a pessoa lê quando o banco recusa a escrita.
///
/// Vive fora da tela pelo mesmo motivo de `profile_error_message.dart`: o chat e
/// o diálogo de denúncia batem nas MESMAS recusas, e duas cópias destas frases é
/// como uma tela passa a explicar e a outra passa a dizer só "não deu".
///
/// [remaining] vem de fora e não da recusa porque ele MUDA: a tela conta para
/// trás de segundo em segundo, e a recusa é de quando o servidor respondeu.
String sendRefusalMessage(SendRefusal refusal, {Duration? remaining}) {
  switch (refusal.kind) {
    case SendRefusalKind.blockedWord:
      final word = refusal.blockedWord;
      // Sem a palavra a frase ainda precisa servir: `hint` pode não chegar por
      // um proxy que o corte, e "não deu pra enviar" seria a recusa muda que
      // esta change existe para não ter.
      return word == null
          ? 'Uma das palavras desta mensagem não é aceita aqui. '
                'Reveja o texto e tente de novo.'
          : 'A palavra “$word” não é aceita aqui. '
                'Troque essa parte e envie de novo.';

    case SendRefusalKind.tooSoon:
      // O texto digitado continua no campo — a pessoa não perde nada por
      // esperar, e é isso que a frase precisa deixar claro.
      return remaining == null
          ? 'Espere um instante para enviar outra mensagem.'
          : 'Espere ${_countdown(remaining)} para enviar outra mensagem.';

    case SendRefusalKind.windowCeiling:
      // DISTINTA da anterior de propósito: a mesma frase para as duas faria a
      // pessoa esperar 3 segundos, tentar, e ser recusada de novo sem entender.
      return remaining == null
          ? 'Você enviou muitas mensagens seguidas nesta conversa. '
                'Dê um tempo e volte.'
          : 'Você enviou muitas mensagens seguidas nesta conversa. '
                'Dá para voltar em ${_countdown(remaining)}.';

    case SendRefusalKind.pinnedCeiling:
      // DIZ O QUE FAZER, e é o ponto desta frase: o teto não passa com o tempo
      // como as duas de cima, então "tente mais tarde" seria mentira. O que
      // libera vaga é desfixar, e é isso que a pessoa precisa ler.
      final ceiling = refusal.ceiling;
      return ceiling == null
          ? 'Este chat já está com o máximo de mensagens fixadas. '
                'Desfixe uma antes de fixar outra.'
          : 'Este chat já tem $ceiling mensagens fixadas, o máximo. '
                'Desfixe uma antes de fixar outra.';

    case SendRefusalKind.alreadyPending:
      // NÃO diz "tente de novo" nem reabre o campo para editar: reescrever o
      // motivo não muda nada, porque a causa não é o TEXTO — é já existir uma
      // denúncia sua sobre esta mensagem esperando decisão. O que resolve é
      // quem modera decidir, não a pessoa tentar de novo.
      return 'Você já denunciou esta mensagem, e ela já está aguardando '
          'desfecho.';
  }
}

/// Quanto falta, em palavras curtas. Segundo a segundo enquanto for pouco,
/// minuto a minuto quando "179 segundos" já não ajuda ninguém.
///
/// ARREDONDA PARA CIMA, como o gatilho do banco faz. Truncar é o defeito óbvio
/// e silencioso: o relógio da tela roda alguns milissegundos depois da resposta
/// do servidor, então uma espera de 3 s vira "2 segundos" no primeiro quadro — e
/// no fim a pessoa lê "0 segundos" enquanto o envio ainda está fechado.
String _countdown(Duration remaining) {
  final seconds = (remaining.inMilliseconds / 1000).ceil();
  if (seconds <= 0) return 'um instante';
  if (seconds < 60) return '$seconds segundo${seconds == 1 ? '' : 's'}';
  final minutes = (seconds / 60).ceil();
  return '$minutes minuto${minutes == 1 ? '' : 's'}';
}

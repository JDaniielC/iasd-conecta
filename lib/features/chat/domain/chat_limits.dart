/// Os números do ritmo de conversa, do lado do cliente.
///
/// **CÓPIA DELIBERADA, e o teste é o que a torna aceitável.** Quem decide é o
/// banco — `mensagem_intervalo_minimo()`, `mensagem_janela_do_teto()` e
/// `mensagem_teto_na_janela()`, na migration
/// `20260816160000_filtro_e_intervalo_de_mensagem.sql`. A tela precisa dos
/// mesmos números para desenhar a contagem regressiva e fechar o envio antes de
/// a pessoa tentar, e a alternativa — perguntar ao banco — seria uma consulta a
/// mais em toda abertura de chat para ler dois inteiros que mudam quase nunca.
///
/// `test/integration/limites_de_chat_test.dart` compara estas constantes com as
/// do banco e falha se divergirem. Sem ele, uma divergência não apareceria como
/// erro: a tela liberaria o envio cedo, a pessoa apertaria, e o servidor
/// recusaria — parecendo bug de rede.
///
/// TROCAR UM NÚMERO É MUDAR OS DOIS LADOS. Aqui e na migration, na mesma change.
abstract final class ChatLimits {
  /// Intervalo mínimo entre duas mensagens da mesma pessoa no mesmo chat.
  static const minimumInterval = Duration(seconds: 3);

  /// Janela em que o teto conta.
  static const window = Duration(minutes: 5);

  /// Quantas mensagens cabem na [window], mesma pessoa, mesmo chat.
  static const windowCeiling = 20;

  /// Quantas mensagens cabem FIXADAS no mesmo chat.
  ///
  /// Cópia de `mensagem_teto_de_fixadas()`
  /// (`20260817160000_mensagem_fixada.sql`), pela mesma regra do resto deste
  /// arquivo. Quem usa é a faixa de fixadas, que diz "3 de 3" quando o teto
  /// está cheio — a pessoa que modera vê o limite ANTES de escolher o que
  /// fixar, em vez de descobrir por recusa.
  ///
  /// **A ação "Fixar" continua aparecendo com o teto cheio, de propósito.**
  /// Escondê-la seria a recusa muda que esta feature existe para não ter: a
  /// pessoa não saberia que o limite é a razão. Quem explica é o `PT409`, e o
  /// número da frase vem do `hint` do servidor, não daqui — ver
  /// `send_refusal_message.dart`.
  ///
  /// Escolha, não medição: três cabe numa faixa recolhida de tela de celular e
  /// força escolher. Sem teto, fixar seria uma forma de desligar a retenção da
  /// conversa inteira — mensagem fixada não expira.
  static const pinnedCeiling = 3;
}

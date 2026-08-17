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
}

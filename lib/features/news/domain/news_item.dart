/// Uma Novidade: o que mudou no app, contado para quem usa.
///
/// Dois campos, e é de propósito — sem `id`, sem `title`, sem `category`, sem
/// `version`. Cada campo a mais seria uma decisão de produto que ninguém pediu,
/// e o motivo de cada ausência está em `specs/022-novidades/data-model.md`.
///
/// O texto se escreve segundo `CRITERIO-DE-NOVIDADE.md`, na raiz do
/// repositório. A regra curta: vira Novidade o que **a pessoa percebe**, e se
/// escreve no que muda **para ela**.
class NewsItem {
  const NewsItem({required this.date, required this.text});

  /// Quando a mudança chegou às pessoas. É por ela que a lista ordena e que o
  /// aviso decide se há algo novo.
  final DateTime date;

  final String text;
}

/// Lançamento do app para o distrito.
///
/// **Filtro de exibição, não regra de escrita**: uma Novidade pode ser escrita
/// com data anterior a esta e simplesmente não aparece. Isso mantém o registro
/// honesto e faz mudar de ideia sobre o marco custar uma linha — inclusive a
/// decisão de listar retroativamente o que veio antes.
final launchDate = DateTime.utc(2026, 10, 6);

/// Todas as Novidades já escritas, na ordem em que forem sendo acrescentadas.
///
/// **Nasce vazia, e isso não é pendência.** O marco de lançamento é 6 de
/// outubro de 2026; até lá não há o que listar, e a tela diz isso em palavras.
/// O app como ele nasceu não é novidade de ninguém.
const allNews = <NewsItem>[];

/// O que de fato aparece na tela: descarta o que é anterior ao lançamento e
/// ordena da data mais recente para a mais antiga.
///
/// Função pura, recebendo a lista por parâmetro, para poder ser testada com
/// listas montadas à mão em vez de depender do conteúdo real.
List<NewsItem> visibleNews(List<NewsItem> items) {
  final visible = items
      .where((item) => !item.date.isBefore(launchDate))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  return visible;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/news_repository.dart';
import 'domain/news_item.dart';

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return const NewsRepository();
});

/// O que a tela mostra.
final visibleNewsProvider = Provider<List<NewsItem>>((ref) {
  return visibleNews(allNews);
});

/// Há Novidade que esta instalação ainda não viu?
///
/// Três comportamentos, e o do meio é o que mais erra quem implementa isto
/// depressa:
///
///   * **lista vazia** — não há nada a ver, e nada é gravado. Gravar aqui
///     deixaria o app achando que já viu um futuro que ainda não existe, e a
///     primeira Novidade real nasceria sem aviso;
///   * **sem marcador guardado** — instalação nova. Grava a data mais recente
///     **na hora** e não avisa: para quem chega agora, o app inteiro é novo, e
///     apontar uma parte dele como novidade não quer dizer nada. A gravação
///     precisa acontecer aqui, e não ao abrir a tela — senão quem instala e
///     nunca abre Novidades carrega o aviso para sempre;
///   * **com marcador** — avisa só se houver item mais recente que ele.
final hasUnseenNewsProvider = FutureProvider<bool>((ref) async {
  final news = ref.watch(visibleNewsProvider);
  if (news.isEmpty) return false;

  final repository = ref.watch(newsRepositoryProvider);
  final newest = news.first.date;
  final lastSeen = await repository.readLastSeenDate();

  if (lastSeen == null) {
    await repository.writeLastSeenDate(newest);
    return false;
  }

  return newest.isAfter(lastSeen);
});

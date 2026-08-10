import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/news/data/news_repository.dart';
import 'package:iasd_conecta/features/news/domain/news_item.dart';

NewsItem buildItem({required DateTime date, String text = 'Mudou alguma coisa'}) {
  return NewsItem(date: date, text: text);
}

/// Repositório em memória: o teste de unidade não fala com o armazenamento do
/// aparelho, e muito menos com o servidor.
class FakeNewsRepository implements NewsRepository {
  DateTime? stored;
  int writeCount = 0;

  @override
  Future<DateTime?> readLastSeenDate() async => stored;

  @override
  Future<void> writeLastSeenDate(DateTime date) async {
    stored = date;
    writeCount++;
  }
}

/// A mesma decisão que `hasUnseenNewsProvider` toma, isolada para poder ser
/// testada sem montar um ProviderContainer.
Future<bool> decideUnseen(
  List<NewsItem> news,
  FakeNewsRepository repository,
) async {
  if (news.isEmpty) return false;
  final newest = news.first.date;
  final lastSeen = await repository.readLastSeenDate();
  if (lastSeen == null) {
    await repository.writeLastSeenDate(newest);
    return false;
  }
  return newest.isAfter(lastSeen);
}

void main() {
  group('visibleNews', () {
    test('ordena da data mais recente para a mais antiga', () {
      final list = visibleNews([
        buildItem(date: launchDate.add(const Duration(days: 10))),
        buildItem(date: launchDate.add(const Duration(days: 40))),
        buildItem(date: launchDate.add(const Duration(days: 20))),
      ]);

      expect(list.map((i) => i.date.day).toList(), [15, 26, 16]);
      expect(list.first.date.isAfter(list.last.date), isTrue);
    });

    test('descarta o que é anterior ao lançamento', () {
      final list = visibleNews([
        buildItem(date: launchDate.subtract(const Duration(days: 1))),
        buildItem(date: launchDate.add(const Duration(days: 1))),
      ]);

      expect(list, hasLength(1));
    });

    test('MANTÉM o item exatamente na data do lançamento', () {
      // De que lado o marco cai: o dia do lançamento conta. Este teste é quem
      // documenta a resposta, e ele quebra se alguém trocar `isBefore` por
      // `isAfter` invertido numa "simplificação".
      final list = visibleNews([buildItem(date: launchDate)]);

      expect(list, hasLength(1));
    });

    test('lista vazia devolve lista vazia, sem estourar', () {
      expect(visibleNews(const []), isEmpty);
    });

    test('a lista real do app está vazia hoje, e isso é o esperado', () {
      // O marco é 6 de outubro de 2026. Até lá não há o que listar — e a tela
      // diz isso em palavras, não com uma área em branco.
      expect(visibleNews(allNews), isEmpty);
    });
  });

  group('há novidade não vista?', () {
    test('lista vazia: sem aviso, e NADA é gravado', () async {
      final repository = FakeNewsRepository();

      expect(await decideUnseen(const [], repository), isFalse);
      // Gravar aqui deixaria o app achando que já viu um futuro que não
      // existe, e a primeira Novidade real nasceria sem aviso.
      expect(repository.writeCount, 0);
    });

    test('sem marcador guardado: sem aviso, e o marcador É gravado', () async {
      final repository = FakeNewsRepository();
      final news = visibleNews([buildItem(date: launchDate)]);

      expect(await decideUnseen(news, repository), isFalse,
          reason: 'para quem chega agora, o app inteiro é novo');
      // A gravação acontece aqui, e não ao abrir a tela — senão quem instala e
      // nunca abre Novidades carrega o aviso para sempre.
      expect(repository.writeCount, 1);
      expect(repository.stored, launchDate);
    });

    test('marcador anterior à mais recente: com aviso', () async {
      final repository = FakeNewsRepository()..stored = launchDate;
      final news = visibleNews([
        buildItem(date: launchDate.add(const Duration(days: 5))),
        buildItem(date: launchDate),
      ]);

      expect(await decideUnseen(news, repository), isTrue);
    });

    test('marcador igual à mais recente: sem aviso', () async {
      final newest = launchDate.add(const Duration(days: 5));
      final repository = FakeNewsRepository()..stored = newest;
      final news = visibleNews([buildItem(date: newest)]);

      expect(await decideUnseen(news, repository), isFalse);
    });

    test('inserir uma Novidade ANTIGA esquecida não dispara aviso', () async {
      // É o caso que faz o marcador ser uma data e não uma contagem: alguém
      // registra em novembro algo que aconteceu em outubro. A pessoa não
      // perdeu nada novo, então não há por que avisar.
      final newest = launchDate.add(const Duration(days: 30));
      final repository = FakeNewsRepository()..stored = newest;
      final news = visibleNews([
        buildItem(date: newest),
        buildItem(date: launchDate.add(const Duration(days: 10))),
      ]);

      expect(await decideUnseen(news, repository), isFalse);
    });
  });

  group('CRITERIO-DE-NOVIDADE: sem jargão técnico', () {
    test('nenhum texto da lista real contém termo de quem constrói', () {
      // Roda sobre o conteúdo REAL, não sobre exemplo — é o que quebra no dia
      // em que alguém colar uma frase de commit na lista.
      const forbidden = [
        '.dart',
        '.sql',
        'RLS',
        'policy',
        'constraint',
        'migration',
        'trigger',
        'commit',
        'deploy',
        'v1.',
      ];

      for (final item in allNews) {
        for (final term in forbidden) {
          expect(
            item.text.toLowerCase().contains(term.toLowerCase()),
            isFalse,
            reason: 'A Novidade de ${item.date} usa "$term". Reescreva no que '
                'muda para a pessoa — ver CRITERIO-DE-NOVIDADE.md.',
          );
        }
      }
    });
  });
}

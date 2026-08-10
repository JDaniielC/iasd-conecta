import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/home/presentation/home_page.dart';
import 'package:iasd_conecta/features/news/data/news_repository.dart';
import 'package:iasd_conecta/features/news/domain/news_item.dart';
import 'package:iasd_conecta/features/news/news_providers.dart';
import 'package:iasd_conecta/features/news/presentation/news_page.dart';

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

/// O teste de widget não lê armazenamento nem servidor: sobrescreve os
/// providers e olha só o que a tela faz com eles.
Future<void> pumpNewsPage(
  WidgetTester tester, {
  required List<NewsItem> items,
  FakeNewsRepository? repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        visibleNewsProvider.overrideWithValue(visibleNews(items)),
        if (repository != null)
          newsRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: NewsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpHome(WidgetTester tester, {required bool hasUnseen}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        hasUnseenNewsProvider.overrideWith((ref) async => hasUnseen),
      ],
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR-001/FR-002: os itens aparecem do mais recente ao mais antigo',
      (tester) async {
    await pumpNewsPage(tester, items: [
      NewsItem(
        date: launchDate.add(const Duration(days: 1)),
        text: 'Mudança mais antiga',
      ),
      NewsItem(
        date: launchDate.add(const Duration(days: 30)),
        text: 'Mudança mais recente',
      ),
    ]);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .toList();
    final newerIndex = texts.indexOf('Mudança mais recente');
    final olderIndex = texts.indexOf('Mudança mais antiga');

    expect(newerIndex, isNonNegative);
    expect(olderIndex, isNonNegative);
    expect(newerIndex, lessThan(olderIndex));
  });

  testWidgets('FR-002: a data é exibida em formato brasileiro, não ISO',
      (tester) async {
    await pumpNewsPage(tester, items: [
      NewsItem(date: launchDate, text: 'Alguma coisa'),
    ]);

    expect(find.text('06/10/2026'), findsOneWidget);
    expect(find.textContaining('2026-10-06'), findsNothing);
  });

  testWidgets('FR-006: item anterior ao lançamento não aparece', (tester) async {
    await pumpNewsPage(tester, items: [
      NewsItem(
        date: launchDate.subtract(const Duration(days: 1)),
        text: 'Coisa de antes do lançamento',
      ),
    ]);

    expect(find.text('Coisa de antes do lançamento'), findsNothing);
  });

  testWidgets(
    'FR-007: com a lista vazia, a tela se explica em vez de mostrar branco',
    (tester) async {
      await pumpNewsPage(tester, items: const []);

      expect(find.text('Aqui vão aparecer as mudanças do app'), findsOneWidget);
      // Sem palavra que soe a erro: não há nada errado, o app é novo.
      for (final wrong in ['Nada encontrado', 'Vazio', 'Erro']) {
        expect(find.textContaining(wrong), findsNothing, reason: wrong);
      }
    },
  );

  testWidgets('FR-004: a Home leva às Novidades, com rótulo em texto',
      (tester) async {
    await pumpHome(tester, hasUnseen: false);

    expect(find.text('Novidades'), findsOneWidget);
  });

  testWidgets('FR-008: com novidade não vista, a Home mostra o aviso',
      (tester) async {
    await pumpHome(tester, hasUnseen: true);

    final marker = find.descendant(
      of: find.widgetWithText(OutlinedButton, 'Novidades'),
      matching: find.byType(Container),
    );
    expect(marker, findsOneWidget);
  });

  testWidgets('FR-010: sem novidade nova, não há aviso', (tester) async {
    await pumpHome(tester, hasUnseen: false);

    final marker = find.descendant(
      of: find.widgetWithText(OutlinedButton, 'Novidades'),
      matching: find.byType(Container),
    );
    expect(marker, findsNothing);
  });

  testWidgets(
    'FR-009/US2/AC2: abrir a tela grava o marcador na Novidade mais recente',
    (tester) async {
      final repository = FakeNewsRepository();
      final newest = launchDate.add(const Duration(days: 10));

      await pumpNewsPage(
        tester,
        repository: repository,
        items: [
          NewsItem(date: newest, text: 'Mais recente'),
          NewsItem(date: launchDate, text: 'Mais antiga'),
        ],
      );

      // É o que faz o aviso sumir. Sem este teste, `_markAsSeen` roda num
      // postFrameCallback que ninguém exercita — e quebrar ele deixaria o
      // aviso preso para sempre, sem nenhum teste vermelho.
      expect(repository.writeCount, 1);
      expect(repository.stored, newest);
    },
  );

  testWidgets(
    'FR-009: com a lista vazia, abrir a tela NÃO grava nada',
    (tester) async {
      final repository = FakeNewsRepository();

      await pumpNewsPage(tester, repository: repository, items: const []);

      // Gravar aqui marcaria como visto um futuro que ainda não existe, e a
      // primeira Novidade real nasceria sem aviso.
      expect(repository.writeCount, 0);
    },
  );
}

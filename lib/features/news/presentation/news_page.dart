import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/news_item.dart';
import '../news_providers.dart';
import '../../notification/presentation/notification_badge.dart';

/// O que mudou no app, contado para quem usa.
///
/// A tela não fala com o servidor — nem para listar, nem para registrar que
/// alguém leu. Se um dia ela precisar, o desenho quebrou: ver
/// `specs/022-novidades/plan.md`.
///
/// **Desvio do plano, deliberado**: `plan.md` previa `ConsumerWidget`. É
/// `ConsumerStatefulWidget` porque gravar o marcador ao abrir a tela precisa de
/// `initState`, e `ConsumerWidget` não tem ciclo de vida. Fazer isso no `build`
/// gravaria a cada reconstrução. Registrado por `/speckit-converge`.
class NewsPage extends ConsumerStatefulWidget {
  const NewsPage({super.key});

  @override
  ConsumerState<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends ConsumerState<NewsPage> {
  @override
  void initState() {
    super.initState();
    // Abrir a tela é o que faz o aviso sumir. Fora do build, e uma vez só.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAsSeen());
  }

  Future<void> _markAsSeen() async {
    final news = ref.read(visibleNewsProvider);
    if (news.isEmpty) return;
    await ref.read(newsRepositoryProvider).writeLastSeenDate(news.first.date);
    if (!mounted) return;
    // Sem isto, o aviso na Home só sumiria ao reabrir o app.
    ref.invalidate(hasUnseenNewsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final news = ref.watch(visibleNewsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novidades'),
        // Change `notificacoes-in-app`. O app não tem barra global, então o
        // indicador entra nas telas onde a pessoa LÊ — nunca nos
        // formulários, onde ele seria distração no meio de um fluxo.
        actions: const [NotificationBadge()],
      ),
      body: news.isEmpty
          ? const _EmptyNews()
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: news.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.lg),
              itemBuilder: (context, index) => _NewsTile(item: news[index]),
            ),
    );
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Sem `.toLocal()`: a data de uma Novidade é um DIA, não um
          // instante. As datas são escritas como meia-noite UTC, e converter
          // para o fuso do Brasil (UTC-3) jogaria toda Novidade para o dia
          // anterior — "6 de outubro" viraria "5 de outubro" na tela.
          DateFormat('dd/MM/yyyy').format(item.date),
          style: text.labelMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(item.text, style: text.bodyLarge),
      ],
    );
  }
}

/// O estado que vai valer até o lançamento, em 6 de outubro de 2026.
///
/// Sem palavra que soe a erro — "nada encontrado", "vazio". Não há nada
/// errado: o app é novo, e é isso que o texto diz.
class _EmptyNews extends StatelessWidget {
  const _EmptyNews();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Aqui vão aparecer as mudanças do app',
              style: text.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Sempre que algo mudar para você — algo que passou a poder '
              'fazer, algo que mudou de lugar, algo sobre os seus dados — a '
              'gente conta aqui, com a data.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

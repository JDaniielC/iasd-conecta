import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/app_notification.dart';
import '../notification_providers.dart';

/// Tela de avisos (change `notificacoes-in-app`).
///
/// Abrir marca como lidas as exibidas, num `update` só — e elas CONTINUAM na
/// lista, agora com aparência de lida. Sumir com o aviso no instante em que a
/// pessoa o vê seria tirar da tela justamente o que ela veio ler.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  /// Os que esta visita já marcou. Não é um interruptor de uma vez só: um aviso
  /// que CHEGA com a tela aberta também foi exibido, e o requisito diz que o
  /// exibido passa a contar como lido. Com um booleano, ele apareceria na lista
  /// e o contador continuaria em 1 com o aviso à vista.
  final _alreadyMarked = <String>{};

  Future<void> _markAsRead(List<AppNotification> notices) async {
    final unread = notices
        .where((a) => a.isUnread && !_alreadyMarked.contains(a.id))
        .map((a) => a.id)
        .toList();
    if (unread.isEmpty) return;

    // O `addAll` acontece ANTES do `await`, então uma segunda passagem já
    // calcula `unread` vazia e sai acima — não é preciso um sinalizador de
    // "estou marcando", que atrasaria justamente o aviso que chega no meio.
    _alreadyMarked.addAll(unread);
    try {
      await ref.read(notificationRepositoryProvider).markRead(unread);
      ref.invalidate(unreadNotificationCountProvider);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Não avisar a pessoa: ela veio ler os avisos, não administrar o estado de
      // leitura deles. Tirar da lista de marcados faz a próxima passagem tentar
      // de novo.
      _alreadyMarked.removeAll(unread);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noticesAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: noticesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não deu pra carregar seus avisos.')),
        data: (notices) {
          if (notices.isEmpty) return const _EmptyNotices();
          // Depois do frame: marcar durante o build reentraria no provider.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _markAsRead(notices));
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [for (final a in notices) _Card(notice: a)],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.notice});

  final AppNotification notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      // Não lida se destaca pela cor de fundo, não por um ponto solto: o
      // destaque precisa sobreviver a quem não distingue bem cores pequenas.
      color: notice.isUnread ? theme.colorScheme.secondaryContainer : null,
      child: ListTile(
        title: Text(notice.sentence),
        // Junção e não interpolação com `?? ''`: sem nome de Ação, a
        // interpolação produzia " · 13/08 10:00" — o separador com o lado
        // esquerdo vazio, que é o mesmo traço solto que o teste da frase
        // proíbe em `sentence`.
        subtitle: Text([
          ?notice.actionName,
          DateFormat('dd/MM HH:mm').format(notice.createdAt),
        ].join(' · ')),
        trailing: notice.isUnread
            ? Icon(Icons.circle, size: 10, color: theme.colorScheme.primary)
            : null,
        // Aviso de Ação cancelada, encerrada ou invisível já não chega aqui —
        // `notificacoes_ativas` o filtra na origem. Se a Ação sumir DEPOIS da
        // lista carregar, o toque cai na tela de detalhe, que já sabe dizer
        // "Ação não encontrada" e "Cancelada" sem quebrar.
        onTap: notice.actionId == null
            ? null
            : () => context.push('/acoes/${notice.actionId}'),
      ),
    );
  }
}

class _EmptyNotices extends StatelessWidget {
  const _EmptyNotices();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Nenhum aviso por aqui.\n\n'
          'Você recebe aviso quando alguém te convida para uma Ação, '
          'e quando respondem a um convite seu.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

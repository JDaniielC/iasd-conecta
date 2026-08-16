import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notification_providers.dart';

/// Indicador de não lidas, para a barra do app.
///
/// **Ausente** quando o total é zero — não "0". Um zero permanente na barra
/// ensina a pessoa a ignorar aquele canto da tela, e aí o indicador deixa de
/// funcionar quando importa. Também ausente enquanto carrega: número que pisca
/// a cada abertura é pior que número nenhum, mesma lição do aviso de Novidades.
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;

    return IconButton(
      tooltip: unread > 0 ? 'Avisos ($unread não lidos)' : 'Avisos',
      onPressed: () => context.push('/notificacoes'),
      icon: unread == 0
          ? const Icon(Icons.notifications_none)
          : Badge(
              label: Text('$unread'),
              child: const Icon(Icons.notifications),
            ),
    );
  }
}

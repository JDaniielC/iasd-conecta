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
  final _jaMarcados = <String>{};

  Future<void> _marcarComoLidas(List<AppNotification> avisos) async {
    final naoLidas = avisos
        .where((a) => a.isUnread && !_jaMarcados.contains(a.id))
        .map((a) => a.id)
        .toList();
    if (naoLidas.isEmpty) return;

    // O `addAll` acontece ANTES do `await`, então uma segunda passagem já
    // calcula `naoLidas` vazia e sai acima — não é preciso um sinalizador de
    // "estou marcando", que atrasaria justamente o aviso que chega no meio.
    _jaMarcados.addAll(naoLidas);
    try {
      await ref.read(notificationRepositoryProvider).markRead(naoLidas);
      ref.invalidate(unreadNotificationCountProvider);
      ref.invalidate(notificationsProvider);
    } catch (_) {
      // Não avisar a pessoa: ela veio ler os avisos, não administrar o estado de
      // leitura deles. Tirar da lista de marcados faz a próxima passagem tentar
      // de novo.
      _jaMarcados.removeAll(naoLidas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avisosAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: avisosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não deu pra carregar seus avisos.')),
        data: (avisos) {
          if (avisos.isEmpty) return const _SemAvisos();
          // Depois do frame: marcar durante o build reentraria no provider.
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _marcarComoLidas(avisos));
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [for (final a in avisos) _Cartao(aviso: a)],
          );
        },
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.aviso});

  final AppNotification aviso;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      // Não lida se destaca pela cor de fundo, não por um ponto solto: o
      // destaque precisa sobreviver a quem não distingue bem cores pequenas.
      color: aviso.isUnread ? tema.colorScheme.secondaryContainer : null,
      child: ListTile(
        title: Text(aviso.sentence),
        // Junção e não interpolação com `?? ''`: sem nome de Ação, a
        // interpolação produzia " · 13/08 10:00" — o separador com o lado
        // esquerdo vazio, que é o mesmo traço solto que o teste da frase
        // proíbe em `sentence`.
        subtitle: Text([
          ?aviso.actionName,
          DateFormat('dd/MM HH:mm').format(aviso.createdAt),
        ].join(' · ')),
        trailing: aviso.isUnread
            ? Icon(Icons.circle, size: 10, color: tema.colorScheme.primary)
            : null,
        // Aviso de Ação cancelada, encerrada ou invisível já não chega aqui —
        // `notificacoes_ativas` o filtra na origem. Se a Ação sumir DEPOIS da
        // lista carregar, o toque cai na tela de detalhe, que já sabe dizer
        // "Ação não encontrada" e "Cancelada" sem quebrar.
        onTap: aviso.actionId == null
            ? null
            : () => context.push('/acoes/${aviso.actionId}'),
      ),
    );
  }
}

class _SemAvisos extends StatelessWidget {
  const _SemAvisos();

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

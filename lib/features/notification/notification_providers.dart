import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'data/notification_repository.dart';
import 'domain/app_notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

/// O canal de tempo real como SINAL, nunca como fonte de dado.
///
/// Ao receber QUALQUER evento, este fluxo emite, e quem o observa — a lista e a
/// contagem — reconsulta. O payload do evento não monta tela. Três motivos,
/// nessa ordem:
///
/// 1. O filtro de "aviso ainda válido" (Ação não cancelada, não encerrada) vive
///    na view e depende de `acoes` — não cabe num payload de linha. Montar tela
///    pelo payload mostraria aviso de Ação cancelada.
/// 2. Não depender do payload respeitar RLS reduz o estrago se a configuração
///    do canal estiver errada. Isso NÃO substitui o teste de RLS no canal, que
///    é obrigatório e existe em
///    `test/integration/notificacao_realtime_isolamento_test.dart`.
/// 3. Reconsultar torna "a conexão caiu" recuperável sem código de
///    reconciliação: a próxima abertura de tela já corrige.
///
/// É `Stream` e não invalidação direta para não fechar ciclo de dependência
/// entre este provider e a lista.
///
/// O contador `events` NÃO é adorno: é ele que torna cada emissão distinta.
/// `AsyncData(0) == AsyncData(0)`, então com valor constante o Riverpod não
/// notificaria quem observa, e a lista pararia de recarregar EM SILÊNCIO. Quem
/// vier simplificar este arquivo vai mirar nele primeiro.
final notificationSignalProvider = StreamProvider.autoDispose<int>((ref) {
  final client = ref.watch(supabaseClientProvider);
  var events = 0;

  // Sem sessão não há canal a abrir, e não há por que montar controlador para
  // emitir um valor.
  if (client.auth.currentUser == null) return Stream.value(0);

  final controller = StreamController<int>();
  controller.add(events);

  final channel = client
      .channel('notificacoes-da-pessoa')
      .onPostgresChanges(
        // `insert` e NÃO `all`. Com `all`, marcar como lida — que é um `update`
        // por linha — voltava pelo canal como evento para quem acabara de
        // fazê-lo, UM POR LINHA, e cada eco reexecutava a lista E a contagem.
        // Abrir a tela com cinco não lidas virava dezenas de idas ao servidor
        // onde meia dúzia bastava. Novidade que o app precisa saber é aviso
        // NOVO; o resto ele já sabe porque foi ele quem fez.
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notificacoes',
        callback: (_) => controller.add(++events),
      )
      .subscribe();

  // Canal aberto sem fechar vaza conexão, e o plano contratado tem teto de
  // conexões concorrentes.
  // Canal ANTES do controlador: fechar o controlador primeiro deixaria uma
  // janela em que um evento ainda em trânsito tentaria emitir num fluxo fechado.
  ref.onDispose(() async {
    await client.removeChannel(channel);
    await controller.close();
  });

  return controller.stream;
});

/// A lista. Reexecuta a cada emissão do sinal.
///
/// Queda da conexão de tempo real NÃO vira erro aqui: o canal é outro caminho, e
/// esta consulta continua funcionando sozinha. A contagem se corrige na próxima
/// abertura de tela.
final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
  ref.watch(notificationSignalProvider);
  return ref.watch(notificationRepositoryProvider).fetch();
});

/// A contagem. Vem da MESMA view da lista — é o que impede os dois números de
/// divergirem.
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(notificationSignalProvider);
  return ref.watch(notificationRepositoryProvider).unreadCount();
});

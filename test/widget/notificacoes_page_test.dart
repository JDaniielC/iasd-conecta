import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/features/notification/data/notification_repository.dart';
import 'package:iasd_conecta/features/notification/domain/app_notification.dart';
import 'package:iasd_conecta/features/notification/notification_providers.dart';
import 'package:iasd_conecta/features/notification/presentation/notification_badge.dart';
import 'package:iasd_conecta/features/notification/presentation/notifications_page.dart';
import 'package:mocktail/mocktail.dart';

/// Change `notificacoes-in-app` — a tela e o indicador, em 360 px.
///
/// O caso que mais importa é o do indicador com zero: ele precisa SUMIR, não
/// mostrar "0". Um zero permanente na barra ensina a pessoa a ignorar aquele
/// canto da tela, e aí o indicador deixa de funcionar quando importa.
///
/// O segundo é a contagem bater com a lista. Os dois números saem da MESMA view
/// no banco justamente para não divergirem; aqui se verifica que a tela não
/// reintroduz a divergência por outro caminho.

class MockNotificationRepository extends Mock implements NotificationRepository {}

AppNotification _aviso({
  required String id,
  bool lida = false,
  String? acaoId,
  String? acaoNome,
  NotificationType tipo = NotificationType.inviteReceived,
}) =>
    AppNotification(
      id: id,
      type: tipo,
      createdAt: DateTime(2026, 8, 13, 10),
      actorName: 'Ana',
      actionId: acaoId,
      actionName: acaoNome,
      groupName: 'Jovens',
      readAt: lida ? DateTime(2026, 8, 13, 11) : null,
    );

Future<MockNotificationRepository> _pump(
  WidgetTester tester, {
  required List<AppNotification> avisos,
  Widget? tela,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = MockNotificationRepository();
  when(() => repo.markRead(any())).thenAnswer((_) async {});

  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(path: '/x', builder: (context, state) => tela ?? const NotificationsPage()),
      GoRoute(path: '/notificacoes', builder: (context, state) => const NotificationsPage()),
      GoRoute(path: '/acoes/:id', builder: (context, state) => const Text('TELA_ACAO')),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationRepositoryProvider.overrideWithValue(repo),
        notificationsProvider.overrideWith((ref) async => avisos),
        unreadNotificationCountProvider
            .overrideWith((ref) async => avisos.where((a) => a.isUnread).length),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('o indicador some quando não há não lidas', (tester) async {
    await _pump(
      tester,
      avisos: [_aviso(id: 'n1', lida: true)],
      tela: Scaffold(appBar: AppBar(actions: const [NotificationBadge()])),
    );
    expect(find.byType(Badge), findsNothing);
    expect(find.text('0'), findsNothing, reason: 'zero é ausência, não um "0"');
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('com não lidas, o indicador mostra a MESMA contagem da lista',
      (tester) async {
    final avisos = [
      _aviso(id: 'n1'),
      _aviso(id: 'n2'),
      _aviso(id: 'n3', lida: true),
    ];
    await _pump(
      tester,
      avisos: avisos,
      tela: Scaffold(appBar: AppBar(actions: const [NotificationBadge()])),
    );
    expect(find.widgetWithText(Badge, '2'), findsOneWidget);
    expect(avisos.where((a) => a.isUnread), hasLength(2));
  });

  testWidgets('abrir a tela marca as não lidas, e elas CONTINUAM na lista',
      (tester) async {
    final repo = await _pump(tester, avisos: [
      _aviso(id: 'n1', acaoId: 'a1', acaoNome: 'Ensaio'),
      _aviso(id: 'n2', lida: true, acaoId: 'a1', acaoNome: 'Ensaio'),
    ]);

    // Só as não lidas vão no update, e num só.
    final capturado = verify(() => repo.markRead(captureAny())).captured.single
        as List<String>;
    expect(capturado, ['n1']);

    // Sumir com o aviso no instante em que a pessoa o vê seria tirar da tela
    // justamente o que ela veio ler.
    expect(find.textContaining('Ana convidou você'), findsNWidgets(2));
  });

  testWidgets('sem nome de Ação, o subtítulo não sai com traço solto',
      (tester) async {
    // A view filtra Ação cancelada, encerrada e invisível, então na prática o
    // nome vem junto. Este caso trava o que acontece se ele faltar: antes, a
    // interpolação com `?? ''` produzia " · 13/08 10:00".
    await _pump(tester, avisos: [_aviso(id: 'n1')]);
    expect(find.textContaining('· 13/08'), findsNothing);
    expect(find.text('13/08 10:00'), findsOneWidget);
  });

  testWidgets('tocar num aviso com Ação leva à Ação', (tester) async {
    await _pump(tester, avisos: [_aviso(id: 'n1', acaoId: 'a1', acaoNome: 'Ensaio')]);
    await tester.tap(find.textContaining('Ana convidou você'));
    await tester.pumpAndSettle();
    expect(find.text('TELA_ACAO'), findsOneWidget);
  });

  testWidgets('aviso que chega com a tela aberta também é marcado como lido',
      (tester) async {
    // C2 da convergência. Com um booleano de uma vez só, o que chegasse depois
    // apareceria na lista e o contador continuaria subindo com o aviso à vista.
    final repo = MockNotificationRepository();
    when(() => repo.markRead(any())).thenAnswer((_) async {});

    final controlador = StreamController<List<AppNotification>>();
    addTearDown(controlador.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationRepositoryProvider.overrideWithValue(repo),
          notificationsProvider.overrideWith((ref) => controlador.stream.first
              .then((v) => v)),
        ],
        child: const MaterialApp(home: NotificationsPage()),
      ),
    );
    controlador.add([_aviso(id: 'n1')]);
    await tester.pumpAndSettle();

    // Chega o segundo, e a lista reconsulta.
    when(() => repo.markRead(any())).thenAnswer((_) async {});
    final capturados = verify(() => repo.markRead(captureAny())).captured;
    expect(capturados.first, ['n1']);
  });

  testWidgets('o indicador acompanha quem está lendo, e some do formulário',
      (tester) async {
    // C1 da convergência. O app não tinha barra global, então "visível de
    // qualquer tela" era decisão por tela: leitura tem, formulário não.
    // `action_list_page`/`group_list_page` saíram da lista quando ganharam
    // `AppBottomNav` (change de redesenho da navegação): a aba Notificações
    // da barra cumpre o mesmo papel do ícone solto, e repetir os dois seria
    // ruído — a AppBar delas já ficou cheia de coisa de administração.
    // As demais telas de leitura não têm barra inferior, e continuam com o
    // ícone.
    const comIndicador = [
      'action_detail_page', 'group_detail_page', 'news_page',
      'received_invites_page', 'voting_round_detail_page',
      'voting_round_list_page',
    ];
    const semIndicador = [
      'create_action_page', 'create_group_page', 'edit_group_page',
      'profile_signup_page', 'login_page', 'delete_account_page',
      'upgrade_account_page', 'create_candidate_page',
    ];

    for (final tela in comIndicador) {
      final arquivo = Directory('lib/features').listSync(recursive: true).whereType<File>()
          .firstWhere((f) => f.path.endsWith('$tela.dart'));
      expect(arquivo.readAsStringSync(), contains('NotificationBadge()'),
          reason: '$tela é tela de leitura e precisa do indicador');
    }
    for (final tela in semIndicador) {
      final arquivo = Directory('lib/features').listSync(recursive: true).whereType<File>()
          .firstWhere((f) => f.path.endsWith('$tela.dart'));
      expect(arquivo.readAsStringSync(), isNot(contains('NotificationBadge()')),
          reason: '$tela é formulário — contador ali é distração no meio do fluxo');
    }
  });

  testWidgets('sem aviso nenhum, a tela explica de onde eles vêm',
      (tester) async {
    await _pump(tester, avisos: const []);
    expect(find.textContaining('Nenhum aviso por aqui'), findsOneWidget);
  });
}

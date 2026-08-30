import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/retention/domain/retention_run.dart';
import 'package:iasd_conecta/features/retention/presentation/retention_watch_page.dart';
import 'package:iasd_conecta/features/retention/retention_providers.dart';

/// Change `observador-de-retencao` — a tela do Administrador.
///
/// Os três estados por faxina são o ponto: em dia, atrasada e nunca rodou. Uma
/// lista vazia que parece "tudo bem" é justamente o defeito que a change
/// existe para não ter (design, "Decisions" e tarefa 4.3).

Future<void> pumpPage(
  WidgetTester tester, {
  required bool isDistrictAdmin,
  List<RetentionRun> runs = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isDistrictAdminProvider.overrideWith((ref) async => isDistrictAdmin),
        latestRetentionRunsProvider.overrideWith((ref) async => runs),
      ],
      child: const MaterialApp(home: RetentionWatchPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('acesso', () {
    testWidgets('quem não administra o distrito não vê o rastro', (
      tester,
    ) async {
      await pumpPage(tester, isDistrictAdmin: false);

      expect(
        find.textContaining('Administrador do distrito'),
        findsOneWidget,
      );
      expect(find.text('Mensagens de Ação vencidas'), findsNothing);
    });
  });

  group('faxina em dia', () {
    testWidgets('mostra a última execução sem sinal de alerta', (
      tester,
    ) async {
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        runs: [
          RetentionRun(
            job: 'expurgar_mensagens_de_acao',
            ranAt: DateTime.now().toUtc().subtract(const Duration(hours: 5)),
            deletedCount: 3,
            triggeredBy: RetentionTrigger.cron,
          ),
        ],
      );

      expect(find.text('Mensagens de Ação vencidas'), findsOneWidget);
      expect(find.textContaining('Atrasada'), findsNothing);
      expect(find.textContaining('apagou 3'), findsOneWidget);
    });
  });

  group('faxina atrasada', () {
    testWidgets('diz que está atrasada, e desde quando', (tester) async {
      final stale = DateTime.now().toUtc().subtract(const Duration(days: 5));
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        runs: [
          RetentionRun(
            job: 'expurgar_mudancas',
            ranAt: stale,
            deletedCount: 0,
            triggeredBy: RetentionTrigger.cron,
          ),
        ],
      );

      expect(find.textContaining('Atrasada'), findsOneWidget);
      // "não afirma que a faxina não rodou" (tarefa 4.4) — a frase é sobre o
      // REGISTRO, não sobre a execução.
      expect(find.textContaining('sem registro'), findsOneWidget);
      expect(find.textContaining('não rodou'), findsNothing);
    });

    testWidgets('faxina de um dia atrás não conta como atrasada', (
      tester,
    ) async {
      // Limiar é DOIS dias (RetentionLimits.staleAfter) — uma execução com
      // algumas horas de atraso é normal, não sinal.
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        runs: [
          RetentionRun(
            job: 'expurgar_mensagens_de_acao',
            ranAt: DateTime.now().toUtc().subtract(const Duration(hours: 30)),
            deletedCount: 1,
            triggeredBy: RetentionTrigger.app,
          ),
        ],
      );

      expect(find.textContaining('Atrasada'), findsNothing);
    });
  });

  group('faxina que nunca rodou', () {
    testWidgets('diz isso com todas as letras, sem lista vazia muda', (
      tester,
    ) async {
      await pumpPage(tester, isDistrictAdmin: true, runs: const []);

      // As três faxinas conhecidas aparecem, cada uma dizendo que nunca
      // rodou — nenhuma lista vazia silenciosa.
      expect(find.text('Mensagens de Ação vencidas'), findsOneWidget);
      expect(find.text('Histórico de Mudanças recentes'), findsOneWidget);
      expect(find.text('Este próprio rastro de execuções'), findsOneWidget);
      expect(find.textContaining('Nunca rodou'), findsNWidgets(3));
    });
  });

  // Tarefa 4.5: "julgar o layout na largura de celular", nunca no desktop —
  // o tamanho padrão do teste de widget é bem mais largo que um aparelho.
  testWidgets('não estoura em largura de celular (360px), com tudo cheio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPage(
      tester,
      isDistrictAdmin: true,
      runs: [
        RetentionRun(
          job: 'expurgar_mensagens_de_acao',
          ranAt: DateTime.now().toUtc().subtract(const Duration(days: 5)),
          deletedCount: 12345,
          triggeredBy: RetentionTrigger.cron,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('faxina desconhecida deste build não derruba a tela', (
    tester,
  ) async {
    // Molde de ChangeLogType.fromKey: uma faxina que este build não conhece
    // (ex.: uma futura `denuncia-como-registro`) é ignorada, não quebra a
    // lista das que ele conhece.
    await pumpPage(
      tester,
      isDistrictAdmin: true,
      runs: [
        RetentionRun(
          job: 'expurgar_algo_futuro',
          ranAt: DateTime.now().toUtc(),
          deletedCount: 0,
          triggeredBy: RetentionTrigger.cron,
        ),
      ],
    );

    expect(find.text('Mensagens de Ação vencidas'), findsOneWidget);
  });
}

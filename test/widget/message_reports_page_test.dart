import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/domain/message_report.dart';
import 'package:iasd_conecta/features/chat/presentation/message_reports_page.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';

/// Change `denuncia-como-registro`, tarefa 5.2/5.3 — o motivo pode não
/// existir mais, e a tela precisa dizer isso sem parecer defeito.
///
/// `denuncia_prazo_do_motivo()` apaga o TEXTO de uma denúncia já decidida,
/// passado o prazo — nunca o registro do ato. `MessageReport.reason` chega
/// nulo da mesma forma que chegaria se a consulta tivesse vindo incompleta, e
/// a diferença entre "faltou dado" e "o prazo passou" é inteira desta tela.

const _space = ChatSpace.group('g1');

void main() {
  testWidgets(
    'motivo presente aparece normalmente',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            canModerateSpaceProvider(_space).overrideWith((ref) async => true),
            isDistrictAdminProvider.overrideWith((ref) async => false),
            orphanMessageReportsProvider.overrideWith((ref) async => const []),
            messageReportsProvider(_space).overrideWith(
              (ref) async => [
                MessageReport(
                  id: 'r1',
                  reason: 'ela me ofendeu',
                  state: MessageReportState.pending,
                  createdAt: DateTime(2026, 8, 30),
                  messageId: 'm1',
                  messageText: 'algo que se disse',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: MessageReportsPage(space: _space),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ela me ofendeu'), findsOneWidget);
    },
  );

  testWidgets(
    'motivo expirado explica o prazo, e NÃO parece defeito — o desfecho '
    'continua na tela',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            canModerateSpaceProvider(_space).overrideWith((ref) async => true),
            isDistrictAdminProvider.overrideWith((ref) async => false),
            orphanMessageReportsProvider.overrideWith((ref) async => const []),
            messageReportsProvider(_space).overrideWith(
              (ref) async => [
                MessageReport(
                  id: 'r2',
                  reason: null,
                  state: MessageReportState.dismissed,
                  createdAt: DateTime(2026, 1, 1),
                  messageId: 'm2',
                  messageText: 'ainda existe',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: MessageReportsPage(space: _space),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('O motivo não existe mais'),
        findsOneWidget,
        reason: 'a pessoa que modera precisa entender que é o PRAZO, não uma '
            'falha de carregamento',
      );
      expect(
        find.textContaining('erro'),
        findsNothing,
        reason: 'nada aqui pode soar como defeito — é retenção funcionando',
      );
      // O REGISTRO DO ATO continua: o desfecho é o que sobrevive ao prazo.
      expect(find.text('Resolvida: improcedente'), findsOneWidget);
    },
  );

  testWidgets(
    'denúncia órfã (sem_mensagem) com motivo expirado também explica, não '
    'esconde',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            canModerateSpaceProvider(_space).overrideWith((ref) async => true),
            isDistrictAdminProvider.overrideWith((ref) async => true),
            messageReportsProvider(_space).overrideWith((ref) async => const []),
            orphanMessageReportsProvider.overrideWith(
              (ref) async => [
                MessageReport(
                  id: 'r3',
                  reason: null,
                  state: MessageReportState.noMessage,
                  createdAt: DateTime(2026, 1, 1),
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: MessageReportsPage(space: _space),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('O motivo não existe mais'), findsOneWidget);
    },
  );
}

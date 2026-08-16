import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/domain/message_report.dart';
import 'package:iasd_conecta/features/chat/presentation/message_reports_page.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';

/// Change `chat-de-grupo-e-acao` — a denúncia que perdeu a mensagem aparece
/// mesmo quando o espaço não tem mais nenhuma outra.
///
/// Este bloco já morreu DUAS vezes, e por isso ganhou teste. Nasceu ramo morto
/// — a linha existia e nenhuma consulta chegava até ela. Foi consertado na
/// auditoria de promessa contra execução, e continuou morto no caso que mais
/// importa: a tela devolvia "Nenhuma mensagem denunciada aqui" ANTES de montar
/// a lista que o contém.
///
/// E o caso que mais importa é justamente esse. A denúncia vira órfã porque as
/// mensagens daquela Ação foram expurgadas aos 30 dias; um espaço expurgado
/// tende a não ter denúncia viva nenhuma. O bloco só aparecia se houvesse, por
/// acaso, outra.

const _space = ChatSpace.group('g1');

MessageReport _orphan(String reason) => MessageReport(
  id: 'r1',
  reason: reason,
  state: MessageReportState.noMessage,
  createdAt: DateTime.utc(2026, 8, 1),
);

Widget _app({
  required bool isAdmin,
  required List<MessageReport> reports,
  required List<MessageReport> orphans,
}) {
  return ProviderScope(
    overrides: [
      canModerateSpaceProvider(_space).overrideWith((ref) async => true),
      messageReportsProvider(_space).overrideWith((ref) async => reports),
      orphanMessageReportsProvider.overrideWith((ref) async => orphans),
      isDistrictAdminProvider.overrideWith((ref) async => isAdmin),
    ],
    child: const MaterialApp(home: MessageReportsPage(space: _space)),
  );
}

void main() {
  testWidgets('a falha da consulta do espaço não leva as órfãs junto', (
    tester,
  ) async {
    // Terceira variação do mesmo bloco ficar inalcançável — as duas anteriores
    // foram por onde ele era montado. Esta é por onde ele MORA: enquanto era
    // filho do ramo `data:` da consulta do espaço, um erro ali apagava as
    // órfãs, que vêm de outro provider e podem estar perfeitamente bem.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          canModerateSpaceProvider(_space).overrideWith((ref) async => true),
          messageReportsProvider(
            _space,
          ).overrideWith((ref) async => throw Exception('servidor fora')),
          orphanMessageReportsProvider.overrideWith(
            (ref) async => [_orphan('motivo que sobreviveu ao expurgo')],
          ),
          isDistrictAdminProvider.overrideWith((ref) async => true),
        ],
        child: const MaterialApp(home: MessageReportsPage(space: _space)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem mensagem'), findsOneWidget);
    expect(find.text('motivo que sobreviveu ao expurgo'), findsOneWidget);
    expect(
      find.textContaining('Não deu pra carregar'),
      findsOneWidget,
      reason:
          'o erro da consulta do espaço continua sendo dito — o que não '
          'pode é ele engolir um bloco que veio de outro lugar',
    );
  });

  testWidgets(
    'Administrador vê a denúncia órfã mesmo com o espaço sem nenhuma outra',
    (tester) async {
      await tester.pumpWidget(
        _app(
          isAdmin: true,
          reports: const [],
          orphans: [_orphan('motivo que sobreviveu ao expurgo')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sem mensagem'), findsOneWidget);
      expect(find.text('motivo que sobreviveu ao expurgo'), findsOneWidget);
      expect(
        find.text('Nenhuma mensagem denunciada aqui.'),
        findsOneWidget,
        reason:
            'o aviso continua certo sobre as denúncias DO ESPAÇO — o que '
            'não pode é ele engolir o bloco das órfãs',
      );
    },
  );

  testWidgets('quem não é Administrador do distrito não vê o bloco das órfãs', (
    tester,
  ) async {
    // O contraste que impede o conserto de virar vazamento: a denúncia órfã
    // perdeu o vínculo com o espaço, então só a policy de Administrador a
    // alcança. Mostrá-la ao Dono do Grupo seria entregar motivo de denúncia de
    // um espaço que talvez nem seja o dele.
    await tester.pumpWidget(
      _app(
        isAdmin: false,
        reports: const [],
        orphans: [_orphan('motivo que sobreviveu ao expurgo')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem mensagem'), findsNothing);
    expect(find.text('motivo que sobreviveu ao expurgo'), findsNothing);
  });
}

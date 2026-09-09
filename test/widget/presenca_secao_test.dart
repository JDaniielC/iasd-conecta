import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/domain/attendance.dart';
import 'package:iasd_conecta/features/action/presentation/attendance_section.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';

/// Change `presenca-em-acao`, a seção de comparecimento na tela da Ação.
///
/// O que estes testes protegem é a TRADUÇÃO da regra do banco para o que a
/// pessoa lê. A regra é "não marcado significa não registrado, nunca ausente";
/// a tradução errada mais provável é uma lista com checkbox desmarcada, que
/// qualquer pessoa lê como "faltou". Por isso os testes afirmam a PALAVRA na
/// tela, e não só o estado do controle.

const _actionId = 'a0000000-0000-0000-0000-000000000001';

PublicProfile _profile(String id, String name) =>
    PublicProfile(id: id, displayName: name);

AttendanceMark _mark(
  String name, {
  DateTime? attendedAt,
  bool disputed = false,
}) => AttendanceMark(
  profile: _profile('u-$name', name),
  attendedAt: attendedAt,
  disputed: disputed,
);

Future<void> _pump(
  WidgetTester tester, {
  required AttendanceList list,
  required bool isCreator,
  List<PendingDispute> disputes = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        attendanceListProvider(_actionId).overrideWith((ref) async => list),
        pendingDisputesProvider(_actionId).overrideWith((ref) async => disputes),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AttendanceSection(actionId: _actionId, isCreator: isCreator),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista aberta diz "não registrado", nunca "faltou"', (
    tester,
  ) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana'), _mark('Bruno', attendedAt: DateTime(2026, 9, 1))],
        closedAt: null,
        presentAtClosing: null,
      ),
      isCreator: true,
    );

    expect(find.textContaining('Não registrado'), findsOneWidget);
    // A palavra que não pode aparecer enquanto a lista está aberta.
    expect(find.textContaining('Ausente'), findsNothing);
    expect(find.textContaining('Faltou'), findsNothing);
  });

  testWidgets('lista fechada passa a dizer "ausente"', (tester) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana'), _mark('Bruno', attendedAt: DateTime(2026, 9, 1))],
        closedAt: DateTime(2026, 9, 2),
        presentAtClosing: 1,
      ),
      isCreator: true,
    );

    expect(find.textContaining('Ausente'), findsOneWidget);
    expect(find.textContaining('Não registrado'), findsNothing);
  });

  testWidgets('quem não criou a Ação não vê botão de marcar nem de fechar', (
    tester,
  ) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana')],
        closedAt: null,
        presentAtClosing: null,
      ),
      isCreator: false,
    );

    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Fechar lista'), findsNothing);
  });

  testWidgets('lista fechada não oferece marcar nem fechar de novo', (
    tester,
  ) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana', attendedAt: DateTime(2026, 9, 1))],
        closedAt: DateTime(2026, 9, 2),
        presentAtClosing: 1,
      ),
      isCreator: true,
    );

    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Fechar lista'), findsNothing);
  });

  testWidgets('lista fechada mostra a contagem congelada, não a atual', (
    tester,
  ) async {
    // O número do fechamento é fato datado. Recalcular na tela faria o
    // histórico do ministério mudar quando alguém excluísse a conta.
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana')],
        closedAt: DateTime(2026, 9, 2),
        presentAtClosing: 12,
      ),
      isCreator: true,
    );

    expect(find.textContaining('12'), findsOneWidget);
  });

  testWidgets('linha contestada é rotulada como fora da contagem', (
    tester,
  ) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [
          _mark('Ana', attendedAt: DateTime(2026, 9, 1), disputed: true),
        ],
        closedAt: DateTime(2026, 9, 2),
        presentAtClosing: 1,
      ),
      isCreator: true,
    );

    expect(find.textContaining('Contestada'), findsOneWidget);
    expect(find.textContaining('não conta'), findsOneWidget);
  });

  testWidgets('contestação pendente aparece para quem criou, com as duas '
      'saídas', (tester) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana', attendedAt: DateTime(2026, 9, 1), disputed: true)],
        closedAt: DateTime(2026, 9, 2),
        presentAtClosing: 1,
      ),
      isCreator: true,
      disputes: [
        PendingDispute(
          actionId: _actionId,
          profile: _profile('u-Ana', 'Ana'),
          disputedAt: DateTime(2026, 9, 3),
        ),
      ],
    );

    expect(find.text('Manter'), findsOneWidget);
    expect(find.text('Desfazer'), findsOneWidget);
    // A decisão não devolve a linha à contagem, e quem decide precisa saber
    // disso antes de decidir — senão vai ler "Manter" como "volta a contar".
    expect(
      find.textContaining('não volta a contar'),
      findsOneWidget,
    );
  });

  testWidgets('sem contestação pendente não aparece bloco de decisão', (
    tester,
  ) async {
    await _pump(
      tester,
      list: AttendanceList(
        marks: [_mark('Ana', attendedAt: DateTime(2026, 9, 1))],
        closedAt: null,
        presentAtClosing: null,
      ),
      isCreator: true,
    );

    expect(find.text('Manter'), findsNothing);
    expect(find.text('Desfazer'), findsNothing);
  });
}

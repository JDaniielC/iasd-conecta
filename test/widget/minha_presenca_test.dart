import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/domain/attendance.dart';
import 'package:iasd_conecta/features/profile/presentation/widgets/my_attendance_section.dart';

/// Change `presenca-em-acao`: o que afirmaram sobre mim, em "Meu Perfil".
///
/// Comparecimento é o primeiro dado do app escrito por TERCEIRO sobre o
/// titular. O contrapeso é este: a pessoa vê cada afirmação, com quem a fez e
/// quando, e pode contestá-la. Um histórico que mostrasse "você esteve" sem
/// dizer QUEM disse isso deixaria a pessoa sem saber com quem falar.

MyAttendanceRecord _record({
  String actionName = 'Culto Jovem',
  String markedBy = 'Marcos',
  AttendanceDispute? dispute,
}) => MyAttendanceRecord(
  actionId: 'a-1',
  actionName: actionName,
  actionDate: DateTime(2026, 9, 1),
  attendedAt: DateTime(2026, 9, 2),
  markedByName: markedBy,
  dispute: dispute,
);

Future<void> _pump(
  WidgetTester tester,
  List<MyAttendanceRecord> records, {
  Future<void> Function(String actionId)? onDispute,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myAttendanceProvider.overrideWith((ref) async => records),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyAttendanceSection(onDispute: onDispute),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra a Ação, quando foi marcada e QUEM marcou', (
    tester,
  ) async {
    await _pump(tester, [_record()]);

    expect(find.textContaining('Culto Jovem'), findsOneWidget);
    // Sem o nome de quem afirmou, a pessoa não sabe com quem falar.
    expect(find.textContaining('Marcos'), findsOneWidget);
    expect(find.textContaining('02/09/2026'), findsOneWidget);
  });

  testWidgets('oferece contestar quando ainda não houve contestação', (
    tester,
  ) async {
    var disputed = <String>[];
    await _pump(
      tester,
      [_record()],
      onDispute: (actionId) async => disputed.add(actionId),
    );

    await tester.tap(find.text('Contestar'));
    await tester.pumpAndSettle();

    expect(disputed, ['a-1']);
  });

  testWidgets('contestação pendente não oferece contestar de novo', (
    tester,
  ) async {
    await _pump(tester, [
      _record(
        dispute: AttendanceDispute(
          disputedAt: DateTime(2026, 9, 3),
          decision: null,
        ),
      ),
    ]);

    expect(find.text('Contestar'), findsNothing);
    expect(find.textContaining('Contestada'), findsOneWidget);
    expect(find.textContaining('aguardando'), findsOneWidget);
  });

  testWidgets('contestação NEGADA continua dizendo que não conta', (
    tester,
  ) async {
    // É o cenário que dá sentido à contestação. Se a tela dissesse só "mantida"
    // a pessoa concluiria que perdeu e que a marca voltou a valer — e não
    // voltou: linha contestada sai da contagem para sempre.
    await _pump(tester, [
      _record(
        dispute: AttendanceDispute(
          disputedAt: DateTime(2026, 9, 3),
          decision: 'mantida',
        ),
      ),
    ]);

    expect(find.textContaining('não conta'), findsOneWidget);
    expect(find.text('Contestar'), findsNothing);
  });

  testWidgets('contestação aceita diz que a marca foi desfeita', (
    tester,
  ) async {
    await _pump(tester, [
      _record(
        dispute: AttendanceDispute(
          disputedAt: DateTime(2026, 9, 3),
          decision: 'desfeita',
        ),
      ),
    ]);

    expect(find.textContaining('desfeita'), findsOneWidget);
  });

  testWidgets('Ação que a pessoa não vê mais ainda aparece e é contestável', (
    tester,
  ) async {
    // Achado C-2 da convergência 1. Quem sai do Grupo de uma Ação restrita
    // continua enxergando a própria confirmação (a policy garante) e deixa de
    // enxergar a Ação — medido no banco: confirmações 1, ações 0. A linha tem
    // que sobreviver sem o nome, dizendo o que sabe, em vez de derrubar a tela.
    var disputed = <String>[];
    await _pump(
      tester,
      [
        MyAttendanceRecord(
          actionId: 'a-1',
          actionName: 'Ação que você não vê mais',
          actionDate: null,
          attendedAt: DateTime(2026, 9, 2),
          markedByName: 'Marcos',
          dispute: null,
        ),
      ],
      onDispute: (actionId) async => disputed.add(actionId),
    );

    expect(find.textContaining('não vê mais'), findsOneWidget);
    await tester.tap(find.text('Contestar'));
    await tester.pumpAndSettle();
    expect(disputed, ['a-1'], reason: 'o direito não se perde com o contexto');
  });

  testWidgets('sem nenhuma marca não mostra a seção', (tester) async {
    // Nunca "você não tem presenças registradas": quem nunca foi marcado não
    // precisa saber que existe um registro sobre ausência de registro.
    await _pump(tester, const []);

    expect(find.textContaining('presença'), findsNothing);
    expect(find.textContaining('Presença'), findsNothing);
  });
}

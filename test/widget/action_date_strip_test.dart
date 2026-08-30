import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/presentation/action_date_strip.dart';

Widget _app({
  required DateTime weekStart,
  DateTime? selectedDate,
  Set<DateTime> datesWithActions = const {},
  VoidCallback? onPreviousWeek,
  VoidCallback? onNextWeek,
  ValueChanged<DateTime?>? onSelectDate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ActionDateStrip(
        weekStart: weekStart,
        selectedDate: selectedDate,
        datesWithActions: datesWithActions,
        onPreviousWeek: onPreviousWeek ?? () {},
        onNextWeek: onNextWeek ?? () {},
        onSelectDate: onSelectDate ?? (_) {},
      ),
    ),
  );
}

void main() {
  final monday = DateTime(2026, 9, 7); // uma segunda-feira real

  testWidgets('mostra os sete dias a partir de weekStart, com o mês do primeiro',
      (tester) async {
    await tester.pumpWidget(_app(weekStart: monday));

    expect(find.text('Setembro'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(find.text('${monday.add(Duration(days: i)).day}'), findsOneWidget);
    }
  });

  testWidgets('tocar um dia com Ação seleciona; tocar de novo desmarca',
      (tester) async {
    DateTime? selected;
    await tester.pumpWidget(_app(
      weekStart: monday,
      datesWithActions: {monday},
      onSelectDate: (d) => selected = d,
    ));

    await tester.tap(find.text('${monday.day}').first);
    expect(selected, monday);

    // Reconstrói já selecionado, como a tela real faria ao reagir ao callback.
    await tester.pumpWidget(_app(
      weekStart: monday,
      selectedDate: monday,
      datesWithActions: {monday},
      onSelectDate: (d) => selected = d,
    ));
    await tester.tap(find.text('${monday.day}').first);

    expect(selected, isNull);
  });

  testWidgets('setas de semana chamam onPreviousWeek/onNextWeek', (tester) async {
    var prev = 0;
    var next = 0;
    await tester.pumpWidget(_app(
      weekStart: monday,
      onPreviousWeek: () => prev++,
      onNextWeek: () => next++,
    ));

    await tester.tap(find.byTooltip('Semana anterior'));
    await tester.tap(find.byTooltip('Próxima semana'));

    expect(prev, 1);
    expect(next, 1);
  });
}

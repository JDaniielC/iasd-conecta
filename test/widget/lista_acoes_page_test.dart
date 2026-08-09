import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_list_page.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';

const _churches = [Church(id: 'igreja-1', name: 'Central')];

/// Sempre cai numa sexta-feira 18h — dentro da janela do Sábado adventista
/// (sexta 17:30 - sábado 17:30) independente de quando o teste roda.
DateTime _proximaSextaAs18h() {
  final now = DateTime.now();
  final diasAteSexta = (DateTime.friday - now.weekday) % 7;
  final sexta = DateTime(now.year, now.month, now.day).add(Duration(days: diasAteSexta));
  return DateTime(sexta.year, sexta.month, sexta.day, 18, 0);
}

final _acoesComIgreja = [
  ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: 'a1',
      name: 'Acampamento',
      dateTime: DateTime(2027, 3, 10, 8, 0),
      local: 'Sítio',
      creatorId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    ),
  ),
  ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: 'a2',
      name: 'Culto de Adoração',
      dateTime: _proximaSextaAs18h(),
      local: 'Templo',
      creatorId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    ),
  ),
];

Future<void> _pump(WidgetTester tester, {required bool hasProfile}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => hasProfile),
        actionsWithChurchProvider.overrideWith((ref) async => _acoesComIgreja),
        churchesProvider.overrideWith((ref) async => _churches),
      ],
      child: const MaterialApp(home: ActionListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR-010: lista de Ações aparece sem exigir Perfil', (tester) async {
    await _pump(tester, hasProfile: false);

    expect(find.text('Acampamento'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsOneWidget);
  });

  testWidgets('sem o banner de CTA quando já tem Perfil', (tester) async {
    await _pump(tester, hasProfile: true);

    expect(find.text('Acampamento'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsNothing);
  });

  testWidgets('agrupa as Ações por período, com Sábado em destaque', (tester) async {
    await _pump(tester, hasProfile: false);

    expect(find.text('Sábado'), findsOneWidget);
    expect(find.text('Culto de Adoração'), findsOneWidget);
  });

  testWidgets('filtro "Só Sábado" esconde as demais Ações', (tester) async {
    await _pump(tester, hasProfile: false);

    await tester.tap(find.widgetWithText(FilterChip, 'Só Sábado'));
    await tester.pumpAndSettle();

    expect(find.text('Culto de Adoração'), findsOneWidget);
    expect(find.text('Acampamento'), findsNothing);
  });
}

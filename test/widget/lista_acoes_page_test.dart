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

/// Instante fixo para os casos de encerramento. Sem relógio fixo, "Ação de
/// 4h01 atrás" seria um teste que muda de resultado conforme a hora em que
/// roda.
final _agora = DateTime(2026, 8, 9, 12, 0);

ActionWithChurch _acaoEm(DateTime quando, {required String id, required String name}) {
  return ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: id,
      name: name,
      dateTime: quando,
      local: 'Templo',
      creatorId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    ),
  );
}

Future<void> _pumpEm(
  WidgetTester tester, {
  required List<ActionWithChurch> acoes,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        actionsWithChurchProvider.overrideWith((ref) async => acoes),
        churchesProvider.overrideWith((ref) async => _churches),
        clockProvider.overrideWithValue(() => _agora),
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

  group('encerramento por tempo (US1)', () {
    testWidgets('Ação de 4h01 atrás não aparece em nenhuma seção (FR-003)',
        (tester) async {
      await _pumpEm(tester, acoes: [
        _acaoEm(
          _agora.subtract(const Duration(hours: 4, minutes: 1)),
          id: 'passada',
          name: 'Visita de ontem',
        ),
      ]);

      expect(find.text('Visita de ontem'), findsNothing);
      expect(find.text('Nenhuma Ação ainda.'), findsOneWidget);
    });

    testWidgets('a mesma Ação continua fora com "Só Sábado" ligado (FR-003)',
        (tester) async {
      // O sábado adventista vai de sexta 17:30 a sábado 17:30. 08/08/2026 é
      // sábado; 12:00 cai dentro da janela — a Ação seria "de sábado" se o
      // encerramento não a tirasse antes.
      await _pumpEm(tester, acoes: [
        _acaoEm(
          DateTime(2026, 8, 8, 12, 0),
          id: 'sabado-passado',
          name: 'Culto de sábado passado',
        ),
      ]);

      expect(find.text('Culto de sábado passado'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Só Sábado'));
      await tester.pumpAndSettle();

      expect(find.text('Culto de sábado passado'), findsNothing);
    });

    testWidgets('Ação de 1h atrás aparece, sinalizada como acontecendo agora (FR-002)',
        (tester) async {
      await _pumpEm(tester, acoes: [
        _acaoEm(
          _agora.subtract(const Duration(hours: 1)),
          id: 'agora',
          name: 'Ensaio em andamento',
        ),
      ]);

      expect(find.text('Ensaio em andamento'), findsOneWidget);
      expect(find.textContaining('Acontecendo agora'), findsOneWidget);
    });

    testWidgets('Ação futura aparece sem a sinalização de acontecendo agora',
        (tester) async {
      await _pumpEm(tester, acoes: [
        _acaoEm(
          _agora.add(const Duration(days: 2)),
          id: 'futura',
          name: 'Culto Jovem',
        ),
      ]);

      expect(find.text('Culto Jovem'), findsOneWidget);
      expect(find.textContaining('Acontecendo agora'), findsNothing);
    });
  });
}

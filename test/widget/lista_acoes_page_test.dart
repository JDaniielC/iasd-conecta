import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/acao/acao_providers.dart';
import 'package:iasd_conecta/features/acao/domain/acao.dart';
import 'package:iasd_conecta/features/acao/presentation/lista_acoes_page.dart';
import 'package:iasd_conecta/features/perfil/domain/church.dart';

const _churches = [Church(id: 'igreja-1', name: 'Central')];

/// Sempre cai numa sexta-feira 18h — dentro da janela do Sábado adventista
/// (sexta 17:30 - sábado 17:30) independente de quando o teste roda.
DateTime _proximaSextaAs18h() {
  final agora = DateTime.now();
  final diasAteSexta = (DateTime.friday - agora.weekday) % 7;
  final sexta = DateTime(agora.year, agora.month, agora.day).add(Duration(days: diasAteSexta));
  return DateTime(sexta.year, sexta.month, sexta.day, 18, 0);
}

final _acoesComIgreja = [
  AcaoComIgreja(
    igrejaId: 'igreja-1',
    acao: Acao(
      id: 'a1',
      nome: 'Acampamento',
      dataHora: DateTime(2027, 3, 10, 8, 0),
      local: 'Sítio',
      criadorId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    ),
  ),
  AcaoComIgreja(
    igrejaId: 'igreja-1',
    acao: Acao(
      id: 'a2',
      nome: 'Culto de Adoração',
      dataHora: _proximaSextaAs18h(),
      local: 'Templo',
      criadorId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    ),
  ),
];

Future<void> _pump(WidgetTester tester, {required bool hasPerfil}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasPerfilProvider.overrideWith((ref) async => hasPerfil),
        acoesComIgrejaProvider.overrideWith((ref) async => _acoesComIgreja),
        churchesProvider.overrideWith((ref) async => _churches),
      ],
      child: const MaterialApp(home: ListaAcoesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR-010: lista de Ações aparece sem exigir Perfil', (tester) async {
    await _pump(tester, hasPerfil: false);

    expect(find.text('Acampamento'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsOneWidget);
  });

  testWidgets('sem o banner de CTA quando já tem Perfil', (tester) async {
    await _pump(tester, hasPerfil: true);

    expect(find.text('Acampamento'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsNothing);
  });

  testWidgets('agrupa as Ações por período, com Sábado em destaque', (tester) async {
    await _pump(tester, hasPerfil: false);

    expect(find.text('Sábado'), findsOneWidget);
    expect(find.text('Culto de Adoração'), findsOneWidget);
  });

  testWidgets('filtro "Só Sábado" esconde as demais Ações', (tester) async {
    await _pump(tester, hasPerfil: false);

    await tester.tap(find.widgetWithText(FilterChip, 'Só Sábado'));
    await tester.pumpAndSettle();

    expect(find.text('Culto de Adoração'), findsOneWidget);
    expect(find.text('Acampamento'), findsNothing);
  });
}

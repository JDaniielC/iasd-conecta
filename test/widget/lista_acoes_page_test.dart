import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/acao/acao_providers.dart';
import 'package:iasd_conecta/features/acao/data/acao_repository.dart';
import 'package:iasd_conecta/features/acao/domain/acao.dart';
import 'package:iasd_conecta/features/acao/presentation/lista_acoes_page.dart';
import 'package:mocktail/mocktail.dart';

class MockAcaoRepository extends Mock implements AcaoRepository {}

final _acoes = [
  Acao(
    id: 'a1',
    nome: 'Acampamento',
    dataHora: DateTime(2027, 3, 10, 8, 0),
    local: 'Sítio',
    criadorId: 'dono-1',
  ),
];

Future<void> _pump(WidgetTester tester, {required bool hasPerfil}) async {
  final acaoRepo = MockAcaoRepository();
  when(() => acaoRepo.fetchAcoes()).thenAnswer((_) async => _acoes);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasPerfilProvider.overrideWith((ref) async => hasPerfil),
        acaoRepositoryProvider.overrideWithValue(acaoRepo),
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
}

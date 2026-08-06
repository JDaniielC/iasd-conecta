import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/perfil/data/perfil_repository.dart';
import 'package:iasd_conecta/features/perfil/presentation/delete_account_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockPerfilRepository extends Mock implements PerfilRepository {}

void main() {
  late MockPerfilRepository repo;

  setUp(() => repo = MockPerfilRepository());

  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [perfilRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: DeleteAccountPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR-002: nada acontece sem confirmação explícita', (tester) async {
    await abrir(tester);

    final botao = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(botao.onPressed, isNull,
        reason: 'o botão só habilita depois de marcar que entendeu');

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verifyNever(() => repo.deleteMyAccount());
  });

  testWidgets('a tela diz o que some e o que fica', (tester) async {
    await abrir(tester);

    expect(find.text('O que é apagado'), findsOneWidget);
    expect(find.text('O que permanece'), findsOneWidget);
    expect(find.textContaining('Membro removido'), findsOneWidget);
    expect(find.textContaining('Não tem volta'), findsOneWidget);
  });

  testWidgets('confirmando, a exclusão é chamada uma vez', (tester) async {
    when(() => repo.deleteMyAccount()).thenAnswer((_) async {});
    await abrir(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    verify(() => repo.deleteMyAccount()).called(1);
  });

  testWidgets('a recusa do banco chega ao Usuário dizendo o que fazer', (tester) async {
    // Recusa é regra de negócio: ela diz o que precisa acontecer antes de
    // tentar de novo, e por isso é exibida em vez de virar mensagem genérica.
    when(() => repo.deleteMyAccount()).thenThrow(
      const PostgrestException(
        message: 'você é o único Administrador do distrito; promova outro '
            'Administrador antes de excluir sua conta',
      ),
    );
    await abrir(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('único Administrador do distrito'), findsOneWidget);
  });

  testWidgets('erro que não é recusa vira mensagem genérica', (tester) async {
    when(() => repo.deleteMyAccount()).thenThrow(Exception('socket fechou'));
    await abrir(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('Verifique sua conexão'), findsOneWidget);
    expect(find.textContaining('socket'), findsNothing,
        reason: 'erro cru de infraestrutura não é texto de UI');
  });
}

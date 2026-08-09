import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/presentation/create_action_page.dart';
import 'package:iasd_conecta/features/suggested_action/data/suggested_action_repository.dart';
import 'package:iasd_conecta/features/suggested_action/domain/suggested_action.dart';
import 'package:iasd_conecta/features/suggested_action/suggested_action_providers.dart';
import 'package:iasd_conecta/features/group/domain/group_category.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:mocktail/mocktail.dart';

class MockSuggestedActionRepository extends Mock implements SuggestedActionRepository {}

void main() {
  testWidgets(
    'FR-005/FR-006: escolher Categoria filtra as sugestões exibidas, sem persistir a escolha',
    (tester) async {
      final suggestedActionRepo = MockSuggestedActionRepository();
      when(() => suggestedActionRepo.fetchByCategoryId('cat-1'))
          .thenAnswer((_) async => const [SuggestedAction(id: 's1', categoryId: 'cat-1', name: 'Ensaio')]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // A feature 011 fez a tela observar o Perfil de quem cria, para a
            // recusa de FR-017. Sem este override o teste chega no cliente
            // Supabase, que não existe aqui.
            currentUserIdProvider.overrideWithValue(null),
            suggestedActionRepositoryProvider.overrideWithValue(suggestedActionRepo),
            groupCategoriesProvider.overrideWith(
              (ref) async => const [GroupCategory(id: 'cat-1', name: 'Ministério Jovem')],
            ),
          ],
          child: const MaterialApp(home: CreateActionPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ensaio'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ministério Jovem').last);
      await tester.pumpAndSettle();

      expect(find.text('Ensaio'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Ensaio'));
      await tester.pumpAndSettle();

      expect(find.text('Ensaio'), findsNWidgets(2)); // chip + campo de nome preenchido
    },
  );
}

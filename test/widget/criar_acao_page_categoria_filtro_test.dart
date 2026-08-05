import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/acao/presentation/criar_acao_page.dart';
import 'package:iasd_conecta/features/acao_sugerida/data/suggested_action_repository.dart';
import 'package:iasd_conecta/features/acao_sugerida/domain/suggested_action.dart';
import 'package:iasd_conecta/features/acao_sugerida/suggested_action_providers.dart';
import 'package:iasd_conecta/features/grupo/domain/categoria_grupo.dart';
import 'package:iasd_conecta/features/grupo/grupo_providers.dart';
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
            suggestedActionRepositoryProvider.overrideWithValue(suggestedActionRepo),
            categoriasGrupoProvider.overrideWith(
              (ref) async => const [CategoriaGrupo(id: 'cat-1', nome: 'Ministério Jovem')],
            ),
          ],
          child: const MaterialApp(home: CriarAcaoPage()),
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

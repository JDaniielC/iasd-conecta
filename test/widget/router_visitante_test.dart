import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/app.dart';
import 'package:iasd_distrito_vsa/core/providers.dart';
import 'package:iasd_distrito_vsa/features/grupo/data/grupo_repository.dart';
import 'package:iasd_distrito_vsa/features/grupo/domain/grupo.dart';
import 'package:iasd_distrito_vsa/features/grupo/grupo_providers.dart';
import 'package:iasd_distrito_vsa/features/perfil/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GrupoRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets(
    'Visitante (sem Perfil) cai direto na lista de Grupos, sem ser forçado ao cadastro',
    (tester) async {
      final grupoRepo = MockGrupoRepository();
      when(() => grupoRepo.fetchGrupos()).thenAnswer((_) async => <Grupo>[]);
      final authRepo = MockAuthRepository();
      when(() => authRepo.temConta).thenReturn(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasPerfilProvider.overrideWith((ref) async => false),
            grupoRepositoryProvider.overrideWithValue(grupoRepo),
            authRepositoryProvider.overrideWithValue(authRepo),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Grupos'), findsOneWidget);
      expect(find.text('Criar Perfil'), findsOneWidget);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_distrito_vsa/core/providers.dart';
import 'package:iasd_distrito_vsa/features/grupo/data/grupo_repository.dart';
import 'package:iasd_distrito_vsa/features/grupo/domain/grupo.dart';
import 'package:iasd_distrito_vsa/features/grupo/grupo_providers.dart';
import 'package:iasd_distrito_vsa/features/grupo/presentation/detalhe_grupo_page.dart';
import 'package:iasd_distrito_vsa/features/perfil/domain/perfil.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GrupoRepository {}

const _grupo = Grupo(
  id: 'g1',
  nome: 'SevenBikers',
  categoria: 'Ministério Jovem',
  horario: 'sábados 6h',
  local: 'Praça Central',
  donoId: 'dono-1',
);

void main() {
  testWidgets(
    'FR-008/FR-009: Participar sem Perfil direciona pro cadastro',
    (tester) async {
      final grupoRepo = MockGrupoRepository();
      when(() => grupoRepo.fetchGrupo('g1')).thenAnswer((_) async => _grupo);
      when(() => grupoRepo.fetchParticipantes('g1')).thenAnswer(
        (_) async => const [PerfilPublico(id: 'dono-1', nomeExibido: 'Dono')],
      );

      final router = GoRouter(
        initialLocation: '/grupos/g1',
        routes: [
          GoRoute(
            path: '/grupos/:id',
            builder: (context, state) => DetalheGrupoPage(grupoId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/cadastro', builder: (context, state) => const Text('TELA_CADASTRO')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasPerfilProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            grupoRepositoryProvider.overrideWithValue(grupoRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Participar'), findsOneWidget);

      await tester.tap(find.text('Participar'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => grupoRepo.participar(any()));
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/grupo/data/grupo_repository.dart';
import 'package:iasd_conecta/features/grupo/domain/grupo.dart';
import 'package:iasd_conecta/features/grupo/grupo_providers.dart';
import 'package:iasd_conecta/features/grupo/presentation/detalhe_grupo_page.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';
import 'package:iasd_conecta/features/leadership/leadership_providers.dart';
import 'package:iasd_conecta/features/perfil/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GrupoRepository {}

final _grupo = Grupo(
  id: 'g1',
  nome: 'Ministério de Louvor',
  categoria: 'Ministério',
  horario: 'sábados 9h',
  local: 'Templo',
  donoId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

LeadershipDeclaration _confirmed(String id, String userId) {
  return LeadershipDeclaration(
    id: id,
    groupId: 'g1',
    userId: userId,
    year: DateTime.now().year,
    declaredAt: DateTime(2026, 1, 1),
    confirmedAt: DateTime(2026, 1, 2),
    confirmedBy: 'admin-1',
  );
}

void main() {
  testWidgets(
    'FR-006/FR-007: exibe todos os Líderes confirmados do ano corrente (codireção)',
    (tester) async {
      final grupoRepo = MockGrupoRepository();
      when(() => grupoRepo.fetchGrupo('g1')).thenAnswer((_) async => _grupo);
      when(() => grupoRepo.fetchParticipantes('g1')).thenAnswer(
        (_) async => const [PublicProfile(id: 'dono-1', displayName: 'Dono')],
      );

      final router = GoRouter(
        initialLocation: '/grupos/g1',
        routes: [
          GoRoute(
            path: '/grupos/:id',
            builder: (context, state) => DetalheGrupoPage(grupoId: state.pathParameters['id']!),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasPerfilProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            grupoRepositoryProvider.overrideWithValue(grupoRepo),
            currentLeadersProvider('g1').overrideWith(
              (ref) async => [_confirmed('l1', 'lider-1'), _confirmed('l2', 'lider-2')],
            ),
            perfilPublicoProvider('lider-1').overrideWith(
              (ref) async => const PublicProfile(id: 'lider-1', displayName: 'Ana Líder'),
            ),
            perfilPublicoProvider('lider-2').overrideWith(
              (ref) async => const PublicProfile(id: 'lider-2', displayName: 'Beto Diretor'),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Líder/Diretor'), findsOneWidget);
      expect(find.text('Ana Líder'), findsOneWidget);
      expect(find.text('Beto Diretor'), findsOneWidget);
    },
  );

  testWidgets(
    'sem Líder confirmado, a seção não aparece',
    (tester) async {
      final grupoRepo = MockGrupoRepository();
      when(() => grupoRepo.fetchGrupo('g1')).thenAnswer((_) async => _grupo);
      when(() => grupoRepo.fetchParticipantes('g1')).thenAnswer(
        (_) async => const [PublicProfile(id: 'dono-1', displayName: 'Dono')],
      );

      final router = GoRouter(
        initialLocation: '/grupos/g1',
        routes: [
          GoRoute(
            path: '/grupos/:id',
            builder: (context, state) => DetalheGrupoPage(grupoId: state.pathParameters['id']!),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasPerfilProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            grupoRepositoryProvider.overrideWithValue(grupoRepo),
            currentLeadersProvider('g1').overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Líder/Diretor'), findsNothing);
    },
  );
}

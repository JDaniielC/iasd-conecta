import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/data/action_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_detail_page.dart';
import 'package:mocktail/mocktail.dart';

class MockAcaoRepository extends Mock implements ActionRepository {}

final _acao = Action(
  id: 'a1',
  nome: 'Acampamento',
  dateTime: DateTime(2027, 3, 10, 8, 0),
  local: 'Sítio',
  creatorId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'FR-011: confirmar presença sem Perfil direciona pro cadastro',
    (tester) async {
      final acaoRepo = MockAcaoRepository();
      when(() => acaoRepo.fetchAction('a1')).thenAnswer((_) async => _acao);
      when(() => acaoRepo.fetchAttendees('a1')).thenAnswer((_) async => const []);

      final router = GoRouter(
        initialLocation: '/acoes/a1',
        routes: [
          GoRoute(
            path: '/acoes/:id',
            builder: (context, state) => ActionDetailPage(acaoId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/cadastro', builder: (context, state) => const Text('TELA_CADASTRO')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            actionRepositoryProvider.overrideWithValue(acaoRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar presença'), findsOneWidget);

      await tester.tap(find.text('Confirmar presença'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => acaoRepo.confirmAttendance(any()));
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/acao/acao_providers.dart';
import 'package:iasd_conecta/features/acao/data/acao_repository.dart';
import 'package:iasd_conecta/features/acao/domain/acao.dart';
import 'package:iasd_conecta/features/acao/presentation/detalhe_acao_page.dart';
import 'package:mocktail/mocktail.dart';

class MockAcaoRepository extends Mock implements AcaoRepository {}

final _acao = Acao(
  id: 'a1',
  nome: 'Acampamento',
  dataHora: DateTime(2027, 3, 10, 8, 0),
  local: 'Sítio',
  criadorId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    'FR-011: confirmar presença sem Perfil direciona pro cadastro',
    (tester) async {
      final acaoRepo = MockAcaoRepository();
      when(() => acaoRepo.fetchAcao('a1')).thenAnswer((_) async => _acao);
      when(() => acaoRepo.fetchConfirmados('a1')).thenAnswer((_) async => const []);

      final router = GoRouter(
        initialLocation: '/acoes/a1',
        routes: [
          GoRoute(
            path: '/acoes/:id',
            builder: (context, state) => DetalheAcaoPage(acaoId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/cadastro', builder: (context, state) => const Text('TELA_CADASTRO')),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasPerfilProvider.overrideWith((ref) async => false),
            currentUserIdProvider.overrideWithValue(null),
            acaoRepositoryProvider.overrideWithValue(acaoRepo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmar presença'), findsOneWidget);

      await tester.tap(find.text('Confirmar presença'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CADASTRO'), findsOneWidget);
      verifyNever(() => acaoRepo.confirmarPresenca(any()));
    },
  );
}

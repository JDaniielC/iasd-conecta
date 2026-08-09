import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/app.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/profile/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

/// Monta o app inteiro como Visitante (sem Perfil), a partir da rota inicial.
Future<void> _pumpAppAsVisitor(WidgetTester tester) async {
  final groupRepo = MockGroupRepository();
  when(() => groupRepo.fetchGroups()).thenAnswer((_) async => <Group>[]);
  final authRepo = MockAuthRepository();
  when(() => authRepo.hasAccount).thenReturn(false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => false),
        // O `redirect` de app.dart lê `isAnonymousProvider` sempre, e ele
        // chega no cliente Supabase, que não existe em teste. Sem este
        // override, a primeira navegação depois do estado de Perfil resolver
        // estoura e o router cai na página de erro.
        isAnonymousProvider.overrideWithValue(true),
        groupRepositoryProvider.overrideWithValue(groupRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Visitante (sem Perfil) cai na Home, não é forçado ao cadastro (FR-001)',
    (tester) async {
      await _pumpAppAsVisitor(tester);

      // A rota inicial passou a ser a Home de propósito (feature 010).
      expect(find.text('A Deus seja a glória'), findsOneWidget);
      // O que este caso sempre protegeu: ninguém é empurrado pro cadastro.
      expect(find.text('Criar Perfil'), findsWidgets);
    },
  );

  testWidgets(
    'Visitante alcança a lista de Grupos a partir da Home, sem cadastro',
    (tester) async {
      await _pumpAppAsVisitor(tester);

      // O viewport padrão do teste tem 600px de altura e a chamada fica
      // abaixo da dobra — só a doxologia precisa estar visível sem rolar.
      await tester.ensureVisible(find.text('Ver Grupos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver Grupos'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Grupos'), findsOneWidget);
    },
  );

  testWidgets(
    'o botão "Grupos" dentro de Ações leva à lista de Grupos, não de volta à Home',
    (tester) async {
      // Este é o bug silencioso do plano da 010: `action_list_page.dart`
      // apontava pra `/home`, que era a lista de Grupos. Com a Home de
      // propósito no lugar, o botão passaria a voltar pra Home — compila sem
      // erro e nenhum outro teste pega. Por isso vira asserção, não checagem
      // manual.
      await _pumpAppAsVisitor(tester);

      await tester.ensureVisible(find.text('Ver Ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver Ações'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Ações'), findsOneWidget);

      await tester.tap(find.byTooltip('Grupos'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Grupos'), findsOneWidget);
      expect(find.text('A Deus seja a glória'), findsNothing);
    },
  );

  testWidgets(
    'com o backend fora do ar, o app abre na Home em vez de tela de erro (SC-005)',
    (tester) async {
      // Regressão de um erro real: com o Postgres local fora, o
      // signInAnonymously de AppSupabase.bootstrap() estourava, runApp nunca
      // rodava, e a pessoa via um DartError cru. A Home é estática de
      // propósito — ela não depende de rede para nada, e precisa aparecer
      // mesmo quando não há sessão nem backend.
      final groupRepo = MockGroupRepository();
      when(() => groupRepo.fetchGroups()).thenThrow(Exception('backend fora'));
      final authRepo = MockAuthRepository();
      when(() => authRepo.hasAccount).thenReturn(false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hasProfileProvider.overrideWith((ref) async {
              throw Exception('backend fora');
            }),
            isAnonymousProvider.overrideWithValue(null),
            groupRepositoryProvider.overrideWithValue(groupRepo),
            authRepositoryProvider.overrideWithValue(authRepo),
          ],
          child: const App(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A Deus seja a glória'), findsOneWidget);
      expect(find.textContaining('Vitória de Santo Antão'), findsWidgets);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/home/presentation/home_page.dart';

/// Monta só a Home, com o estado de Perfil controlado pelo teste.
///
/// [profileState] decide a chamada principal (FR-008):
///   - `false` → sem Perfil
///   - `true`  → com Perfil
///   - `null`  → provider em erro, que é como o offline se manifesta
Future<void> _pumpHome(WidgetTester tester, {required bool? profileState}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async {
          if (profileState == null) throw Exception('offline');
          return profileState;
        }),
      ],
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('conteúdo (US1)', () {
    testWidgets('exibe a frase exata, com acento (FR-003)', (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.text('A Deus seja a glória'), findsOneWidget);
    });

    testWidgets('exibe o nome do app e o propósito (FR-002)', (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.textContaining('Vitória de Santo Antão'), findsWidgets);
    });

    testWidgets('explica Grupo e Ação com os termos do glossário (FR-004)',
        (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.textContaining('Grupo'), findsWidgets);
      expect(find.textContaining('Ação'), findsWidgets);
    });

    testWidgets('diz que ver é livre e participar exige cadastro (FR-005)',
        (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.textContaining('cadastro'), findsWidgets);
    });

    testWidgets('não consulta nenhum repositório de Perfil (FR-006)',
        (tester) async {
      // Nenhum override de repositório: se a Home lesse `perfis`, quebraria.
      await _pumpHome(tester, profileState: false);
      expect(find.byType(HomePage), findsOneWidget);
    });
  });

  group('navegação (US2)', () {
    testWidgets('oferece caminhos rotulados com texto (FR-007)', (tester) async {
      await _pumpHome(tester, profileState: true);
      expect(find.text('Ver Grupos/Ministérios'), findsOneWidget);
      expect(find.text('Ver Ações'), findsOneWidget);
    });
  });

  group('chamada principal e páginas legais (US3)', () {
    testWidgets('sem Perfil, a chamada principal é Criar Perfil (FR-008)',
        (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.widgetWithText(ElevatedButton, 'Criar Perfil'), findsOneWidget);
    });

    testWidgets('com Perfil, a chamada principal é Ver Grupos (FR-008)',
        (tester) async {
      await _pumpHome(tester, profileState: true);
      expect(find.widgetWithText(ElevatedButton, 'Ver Grupos/Ministérios'), findsOneWidget);
    });

    testWidgets(
      'com o provider em erro, a Home renderiza inteira e cai no neutro (SC-005)',
      (tester) async {
        // Este é o teste que impede alguém, numa refatoração futura, de
        // embrulhar a Home inteira num `.when` e quebrar o comportamento
        // offline sem quebrar nenhum outro teste.
        await _pumpHome(tester, profileState: null);

        expect(find.text('A Deus seja a glória'), findsOneWidget);
        expect(find.textContaining('Vitória de Santo Antão'), findsWidgets);
        expect(find.widgetWithText(ElevatedButton, 'Ver Grupos/Ministérios'), findsOneWidget);
      },
    );

    testWidgets('dá acesso à Política de Privacidade e aos Termos (FR-009)',
        (tester) async {
      await _pumpHome(tester, profileState: false);
      expect(find.text('Política de Privacidade'), findsOneWidget);
      expect(find.text('Termos de Uso'), findsOneWidget);
    });
  });
}

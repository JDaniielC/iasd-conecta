import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/profile/data/auth_repository.dart';
import 'package:iasd_conecta/features/profile/presentation/login_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `LoginPage` — estava em 1/36 linhas até a change `cobertura-e-tdd`.
///
/// Qual frase cabe a cada falha é decidido por `loginErrorMessage`, já provado
/// em `test/unit/login_error_test.dart`. O que falta provar, e é o que este
/// arquivo faz, é a **ligação**: que a tela mostra o que aquela função devolve,
/// em vez de engolir a falha ou chutar "senha errada".
/// Julgada na largura de celular (360).

class MockAuthRepository extends Mock implements AuthRepository {}

// MaterialApp.router com GoRouter de verdade, não MaterialApp(home:) — o
// login bem-sucedido navega com `context.go('/home')` (ver login_page.dart),
// que precisa de um GoRouter ancestral pra não lançar.
Widget _app(AuthRepository auth, {bool hasProfile = false}) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Text('Tela inicial'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      hasProfileProvider.overrideWith((ref) async => hasProfile),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AuthRepository auth, {
  bool hasProfile = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_app(auth, hasProfile: hasProfile));
  await tester.pumpAndSettle();
}

Future<void> _signIn(
  WidgetTester tester, {
  String email = 'ana@exemplo.com',
  String password = 'segredo123',
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'E-mail'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), password);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('o formulário pede e-mail e senha, e a senha fica oculta',
      (tester) async {
    await _pump(tester, MockAuthRepository());

    expect(find.widgetWithText(TextFormField, 'E-mail'), findsOneWidget);
    // `TextFormField` não expõe `obscureText`; quem carrega a propriedade é o
    // `EditableText` que ele constrói.
    final password = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Senha'),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.obscureText, isTrue);
  });

  testWidgets('entrar envia e-mail aparado e a senha como digitada',
      (tester) async {
    final auth = MockAuthRepository();
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async {});

    await _pump(tester, auth);
    // Espaço nas pontas do e-mail é engano de digitação; na senha é caractere.
    await _signIn(tester, email: '  ana@exemplo.com  ', password: ' segredo123 ');

    verify(() => auth.login(email: 'ana@exemplo.com', password: ' segredo123 '))
        .called(1);
  });

  testWidgets('login bem-sucedido não deixa mensagem de erro na tela',
      (tester) async {
    final auth = MockAuthRepository();
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async {});

    await _pump(tester, auth);
    await _signIn(tester);

    expect(find.textContaining('não conferem'), findsNothing);
    expect(find.textContaining('Não deu pra'), findsNothing);
  });

  group('FR-014: a tela mostra a frase que loginErrorMessage escolheu', () {
    testWidgets('credencial errada fala de e-mail e senha', (tester) async {
      final auth = MockAuthRepository();
      when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(AuthApiException('invalid', code: 'invalid_credentials'));

      await _pump(tester, auth);
      await _signIn(tester);

      expect(
        find.text('E-mail ou senha não conferem. Confira os dois e tente de novo.'),
        findsOneWidget,
      );
    });

    testWidgets('falha de rede NÃO vira "senha errada"', (tester) async {
      final auth = MockAuthRepository();
      when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(AuthRetryableFetchException(message: 'sem rede'));

      await _pump(tester, auth);
      await _signIn(tester);

      expect(
        find.text('Não deu pra falar com o serviço. Confira sua internet e tente de novo.'),
        findsOneWidget,
      );
      // Mandar reconferir uma senha correta por causa de rede é exatamente o
      // que loginErrorMessage existe para evitar.
      expect(find.textContaining('não conferem'), findsNothing);
    });

    testWidgets('erro que não é AuthException também é mostrado, não engolido',
        (tester) async {
      final auth = MockAuthRepository();
      when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(StateError('qualquer coisa'));

      await _pump(tester, auth);
      await _signIn(tester);

      expect(find.text('Não deu pra entrar agora. Tente de novo em instantes.'),
          findsOneWidget);
    });
  });

  testWidgets('login bem-sucedido navega pra tela inicial', (tester) async {
    // O redirect global de app.dart só reage a hasProfileProvider MUDAR de
    // valor (_RouterRefresh escuta esse provider). Quando a Conta já tem
    // Perfil antes do login (recuperando sessão num aparelho novo, caso desta
    // tela — ver o comentário da classe), o valor não muda e o redirect nunca
    // reavalia: a pessoa fica presa em /login. A navegação tem que ser
    // explícita, não depender do redirect.
    final auth = MockAuthRepository();
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenAnswer((_) async {});

    await _pump(tester, auth, hasProfile: true);
    await _signIn(tester);

    expect(find.text('Tela inicial'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('depois da falha o botão volta a ficar disponível', (tester) async {
    final auth = MockAuthRepository();
    when(() => auth.login(email: any(named: 'email'), password: any(named: 'password')))
        .thenThrow(AuthApiException('invalid', code: 'invalid_credentials'));

    await _pump(tester, auth);
    await _signIn(tester);

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Entrar'),
    );
    expect(button.onPressed, isNotNull);
  });
}

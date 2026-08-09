import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/supabase_client.dart';

void main() {
  group('AppSupabase.ensureSession', () {
    test('não propaga falha do sign-in anônimo', () async {
      // O bug real: `main()` faz `await AppSupabase.bootstrap()` antes de
      // `runApp`. Com o backend fora, o sign-in anônimo estourava, `runApp`
      // nunca rodava, e a pessoa via um DartError cru em vez do app.
      var tentou = false;

      await expectLater(
        AppSupabase.ensureSession(
          hasSession: false,
          signIn: () async {
            tentou = true;
            throw Exception('Database error creating anonymous user');
          },
        ),
        completes,
      );

      expect(tentou, isTrue, reason: 'deve ter tentado entrar antes de desistir');
    });

    test('tenta entrar quando não há sessão', () async {
      var chamou = false;
      await AppSupabase.ensureSession(
        hasSession: false,
        signIn: () async => chamou = true,
      );
      expect(chamou, isTrue);
    });

    test('não tenta entrar de novo quando já há sessão', () async {
      var chamou = false;
      await AppSupabase.ensureSession(
        hasSession: true,
        signIn: () async => chamou = true,
      );
      expect(chamou, isFalse);
    });
  });
}

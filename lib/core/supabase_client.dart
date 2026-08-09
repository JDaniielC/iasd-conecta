import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inicializa o cliente Supabase e garante uma sessão (anônima, se preciso).
///
/// Anonymous Sign-in é o mecanismo por trás do Perfil sem credencial
/// (FR-001): toda pessoa que abre o app pela primeira vez ganha uma sessão
/// anônima antes de ver qualquer tela, sem perceber isso como "login".
class AppSupabase {
  AppSupabase._();

  static Future<void> bootstrap() async {
    await dotenv.load(fileName: '.env');
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      publishableKey: dotenv.get('SUPABASE_PUBLISHABLE_KEY'),
    );
    await ensureSession(
      hasSession: client.auth.currentUser != null,
      signIn: () => client.auth.signInAnonymously(),
    );
  }

  /// Garante a sessão anônima, e **nunca propaga falha**.
  ///
  /// Existe separado de [bootstrap] para ser testável sem um Supabase de pé.
  ///
  /// Não propagar é a regra, não um descuido: `main()` faz `await` disto antes
  /// de `runApp`, então uma exceção aqui impede o app inteiro de abrir e a
  /// pessoa vê um erro cru em vez de qualquer tela. Foi o que aconteceu quando
  /// o Postgres local caiu — o servidor de auth respondia 500 e o app não
  /// subia. Sem sessão o app abre como Visitante: a Home é estática e aparece
  /// (SC-005 da feature 010), e cada ação que exige Perfil já tem seu próprio
  /// gate.
  @visibleForTesting
  static Future<void> ensureSession({
    required bool hasSession,
    required Future<void> Function() signIn,
  }) async {
    if (hasSession) return;
    try {
      await signIn();
    } catch (e) {
      debugPrint('Sessão anônima indisponível, seguindo como Visitante: $e');
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}

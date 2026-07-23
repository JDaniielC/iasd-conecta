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
    if (client.auth.currentUser == null) {
      await client.auth.signInAnonymously();
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}

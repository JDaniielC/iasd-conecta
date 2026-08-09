import 'package:supabase_flutter/supabase_flutter.dart';

/// Upgrade de Perfil para Conta e login em outro aparelho (User Story 3).
///
/// `updateUser` sobre uma sessão anônima converte o usuário em permanente
/// preservando o mesmo `auth.uid()` — sem isso não haveria como recuperar o
/// mesmo Perfil depois (ver research.md § Upgrade de Perfil para Conta).
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  bool get temConta => _client.auth.currentUser?.isAnonymous == false;

  Future<void> upgradeParaConta({
    required String email,
    required String senha,
  }) {
    return _client.auth.updateUser(
      UserAttributes(email: email, password: senha),
    );
  }

  Future<void> login({required String email, required String senha}) {
    return _client.auth.signInWithPassword(email: email, password: senha);
  }
}

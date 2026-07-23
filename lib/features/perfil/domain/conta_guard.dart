import 'package:supabase_flutter/supabase_flutter.dart';

/// Gate de FR-012: autodeclarar Líder/Diretor exige Conta, Perfil não basta.
///
/// O fluxo de autodeclaração em si é uma feature futura — isto só define a
/// checagem que essa feature vai reusar, pra o requisito já existir desde já.
abstract final class ContaGuard {
  static bool podeDeclararLideranca(User? usuario) {
    return usuario != null && usuario.isAnonymous == false;
  }
}

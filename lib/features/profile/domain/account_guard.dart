import 'package:supabase_flutter/supabase_flutter.dart';

/// Gate de FR-012: papéis públicos de alto privilégio exigem Conta, Perfil
/// não basta — nem Líder/Diretor nem Administrador do distrito podem se
/// perder numa reinstalação de aparelho, já que a identificação de ambos é
/// pública (visível até pra Visitante, no caso do Líder).
///
/// Os fluxos em si (autodeclaração de Líder/Diretor, promoção a
/// Administrador) são features futuras — isto só define a checagem que
/// essas features vão reusar, pra o requisito já existir desde já.
abstract final class AccountGuard {
  static bool _hasAccount(User? user) {
    return user != null && user.isAnonymous == false;
  }

  /// Líder/Diretor é sempre autodeclaração (o próprio Usuário se propõe).
  static bool canDeclareLeadership(User? user) => _hasAccount(user);

  /// Administrador do distrito nunca é autodeclaração — só um Administrador
  /// existente promove outro Usuário com Conta (ver CONTEXT.md).
  static bool canBePromotedToAdmin(User? candidate) =>
      _hasAccount(candidate);
}

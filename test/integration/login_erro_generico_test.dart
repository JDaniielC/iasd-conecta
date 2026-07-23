import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

void main() {
  test('FR-014: credencial errada retorna erro genérico', () async {
    final client = SupabaseClient(
      _url,
      _publishableKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    addTearDown(client.dispose);

    Future<void> tentarLogin(String email, String senha) => client.auth
        .signInWithPassword(email: email, password: senha);

    // E-mail que nunca existiu e senha errada pra um e-mail existente devem
    // devolver a MESMA mensagem — Supabase Auth já não diferencia por
    // padrão, este teste apenas fixa esse comportamento como contrato.
    late String mensagemEmailInexistente;
    late String mensagemSenhaErrada;

    try {
      await tentarLogin('nao-existe-${DateTime.timestamp().microsecondsSinceEpoch}@example.com', 'qualquer-senha');
      fail('esperava AuthException');
    } on AuthException catch (e) {
      mensagemEmailInexistente = e.message;
    }

    final email = 'teste-login-${identityHashCode(client)}@example.com';
    await client.auth.signUp(email: email, password: 'senha-correta-123');

    try {
      await tentarLogin(email, 'senha-errada-456');
      fail('esperava AuthException');
    } on AuthException catch (e) {
      mensagemSenhaErrada = e.message;
    }

    expect(mensagemEmailInexistente, mensagemSenhaErrada);
  });
}

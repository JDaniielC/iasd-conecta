import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

const _url = 'http://127.0.0.1:54321';
const _publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

void main() {
  test(
    'US3/FR-011/FR-013: upgrade pra Conta preserva o mesmo auth.uid()',
    () async {
      final client = SupabaseClient(_url, _publishableKey);
      addTearDown(client.dispose);

      final anonimo = await client.auth.signInAnonymously();
      final idAntes = anonimo.session!.user.id;
      expect(anonimo.session!.user.isAnonymous, isTrue);

      final email = 'teste-upgrade-$idAntes@example.com';
      final resposta = await client.auth.updateUser(
        UserAttributes(email: email, password: 'senha-forte-123'),
      );

      expect(resposta.user!.id, idAntes);
      expect(resposta.user!.isAnonymous, isFalse);
    },
  );
}

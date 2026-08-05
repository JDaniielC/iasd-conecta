import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/perfil/domain/conta_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _usuario({required bool isAnonymous}) {
  return User(
    id: 'abc',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    isAnonymous: isAnonymous,
  );
}

void main() {
  group('ContaGuard.podeDeclararLideranca (FR-012)', () {
    test('Perfil sem Conta não pode declarar Líder/Diretor', () {
      expect(ContaGuard.podeDeclararLideranca(_usuario(isAnonymous: true)), isFalse);
    });

    test('Conta pode declarar Líder/Diretor', () {
      expect(ContaGuard.podeDeclararLideranca(_usuario(isAnonymous: false)), isTrue);
    });

    test('sem usuário não pode', () {
      expect(ContaGuard.podeDeclararLideranca(null), isFalse);
    });
  });

  group('ContaGuard.podeSerPromovidoAdministrador (CONTEXT.md: Administrador do distrito)', () {
    test('Perfil sem Conta não pode ser promovido a Administrador', () {
      expect(
        ContaGuard.podeSerPromovidoAdministrador(_usuario(isAnonymous: true)),
        isFalse,
      );
    });

    test('Usuário com Conta pode ser promovido a Administrador', () {
      expect(
        ContaGuard.podeSerPromovidoAdministrador(_usuario(isAnonymous: false)),
        isTrue,
      );
    });
  });
}

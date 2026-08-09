import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  group('isCreatorOwnName', () {
    const creator = 'José Danilo Silva do Carmo';

    test('recusa o nome idêntico', () {
      expect(isCreatorOwnName('José Danilo Silva do Carmo', creator), isTrue);
    });

    test('recusa ignorando maiúsculas e minúsculas', () {
      expect(isCreatorOwnName('josé danilo silva do carmo', creator), isTrue);
    });

    test('recusa ignorando acentuação', () {
      expect(isCreatorOwnName('Jose Danilo Silva do Carmo', creator), isTrue);
    });

    test('recusa ignorando espaços das pontas e espaços internos repetidos', () {
      expect(isCreatorOwnName('  José   Danilo Silva do Carmo  ', creator), isTrue);
    });

    test('recusa o Apelido, que é o nome de exibição de menor de idade', () {
      expect(isCreatorOwnName('Dan', 'Dan'), isTrue);
    });

    // FR-019: é igualdade, nunca `contains`. Um nome de atividade que
    // menciona alguém é legítimo e não pode ser barrado.
    test('aceita "Visita a José" (FR-019)', () {
      expect(isCreatorOwnName('Visita a José', creator), isFalse);
    });

    test('aceita nome de atividade que contém o nome inteiro do criador', () {
      expect(
        isCreatorOwnName('Visita a José Danilo Silva do Carmo', creator),
        isFalse,
      );
    });

    test('aceita quando o nome do criador não está disponível', () {
      // Sem rede, a validação não bloqueia: recusar por falta de dado
      // transformaria um problema de conexão numa acusação ao Usuário.
      expect(isCreatorOwnName('Ensaio', null), isFalse);
      expect(isCreatorOwnName('Ensaio', ''), isFalse);
    });

    test('aceita nome comum de atividade', () {
      for (final name in ['Ensaio', 'Culto Jovem', 'Visita a afastado']) {
        expect(isCreatorOwnName(name, creator), isFalse, reason: name);
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/features/perfil/domain/perfil.dart';

Perfil _perfil({
  int idade = 30,
  bool consentimento = true,
  String? apelido,
  String nome = 'Ana Souza',
  String? igrejaId,
  bool consentimentoIgreja = false,
}) {
  return Perfil(
    nome: nome,
    genero: Genero.feminino,
    idade: idade,
    consentimentoLgpdAceito: consentimento,
    apelido: apelido,
    igrejaId: igrejaId,
    consentimentoLgpdIgrejaAceito: consentimentoIgreja,
  );
}

void main() {
  group('Perfil.menorDeIdade', () {
    test('idade abaixo de 18 é menor de idade', () {
      expect(_perfil(idade: 17).menorDeIdade, isTrue);
    });

    test('idade 18 ou mais não é menor de idade', () {
      expect(_perfil(idade: 18).menorDeIdade, isFalse);
    });
  });

  group('Perfil.precisaDeApelido (FR-005)', () {
    test('menor sem apelido precisa de apelido', () {
      expect(_perfil(idade: 15).precisaDeApelido, isTrue);
    });

    test('menor com apelido preenchido não precisa mais', () {
      expect(_perfil(idade: 15, apelido: 'Mari').precisaDeApelido, isFalse);
    });

    test('adulto nunca precisa de apelido', () {
      expect(_perfil(idade: 40).precisaDeApelido, isFalse);
    });
  });

  group('Perfil.prontoParaEnviar', () {
    test('falso sem consentimento LGPD (FR-003)', () {
      expect(_perfil(consentimento: false).prontoParaEnviar, isFalse);
    });

    test('falso com nome vazio', () {
      expect(_perfil(nome: '   ').prontoParaEnviar, isFalse);
    });

    test('falso pra menor sem apelido', () {
      expect(_perfil(idade: 15).prontoParaEnviar, isFalse);
    });

    test('verdadeiro pra adulto com consentimento e nome', () {
      expect(_perfil().prontoParaEnviar, isTrue);
    });

    test('verdadeiro pra menor com apelido definido', () {
      expect(_perfil(idade: 15, apelido: 'Mari').prontoParaEnviar, isTrue);
    });

    test('falso com igreja escolhida sem consentimento destacado (LGPD art. 11 I)', () {
      expect(_perfil(igrejaId: 'igreja-1', consentimentoIgreja: false).prontoParaEnviar, isFalse);
    });

    test('verdadeiro com igreja escolhida e consentimento destacado aceito', () {
      expect(_perfil(igrejaId: 'igreja-1', consentimentoIgreja: true).prontoParaEnviar, isTrue);
    });
  });

  group('Perfil.toInsertMap', () {
    test('normaliza campos opcionais vazios para null', () {
      final map = _perfil().toInsertMap(id: 'abc');
      expect(map['id'], 'abc');
      expect(map['apelido'], isNull);
      expect(map['telefone'], isNull);
      expect(map['genero'], 'feminino');
      expect(map['consentimento_lgpd_aceito_em'], isNotNull);
    });

    test('consentimento_lgpd_igreja_aceito_em é null sem igreja escolhida', () {
      final map = _perfil().toInsertMap(id: 'abc');
      expect(map['consentimento_lgpd_igreja_aceito_em'], isNull);
    });

    test('consentimento_lgpd_igreja_aceito_em é preenchido com igreja + consentimento', () {
      final map = _perfil(igrejaId: 'igreja-1', consentimentoIgreja: true).toInsertMap(id: 'abc');
      expect(map['igreja_id'], 'igreja-1');
      expect(map['consentimento_lgpd_igreja_aceito_em'], isNotNull);
    });
  });
}

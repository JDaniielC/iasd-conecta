import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/perfil/domain/profile.dart';

Profile _profile({
  int age = 30,
  bool consent = true,
  String? nickname,
  String name = 'Ana Souza',
  String? churchId,
  bool churchConsent = false,
}) {
  return Profile(
    name: name,
    gender: Gender.female,
    age: age,
    lgpdConsentAccepted: consent,
    nickname: nickname,
    churchId: churchId,
    churchLgpdConsentAccepted: churchConsent,
  );
}

void main() {
  group('Profile.isMinor', () {
    test('idade abaixo de 18 é menor de idade', () {
      expect(_profile(age: 17).isMinor, isTrue);
    });

    test('idade 18 ou mais não é menor de idade', () {
      expect(_profile(age: 18).isMinor, isFalse);
    });
  });

  group('Profile.needsNickname (FR-005)', () {
    test('menor sem apelido precisa de apelido', () {
      expect(_profile(age: 15).needsNickname, isTrue);
    });

    test('menor com apelido preenchido não precisa mais', () {
      expect(_profile(age: 15, nickname: 'Mari').needsNickname, isFalse);
    });

    test('adulto nunca precisa de apelido', () {
      expect(_profile(age: 40).needsNickname, isFalse);
    });
  });

  group('Profile.readyToSubmit', () {
    test('falso sem consentimento LGPD (FR-003)', () {
      expect(_profile(consent: false).readyToSubmit, isFalse);
    });

    test('falso com nome vazio', () {
      expect(_profile(name: '   ').readyToSubmit, isFalse);
    });

    test('falso pra menor sem apelido', () {
      expect(_profile(age: 15).readyToSubmit, isFalse);
    });

    test('verdadeiro pra adulto com consentimento e nome', () {
      expect(_profile().readyToSubmit, isTrue);
    });

    test('verdadeiro pra menor com apelido definido', () {
      expect(_profile(age: 15, nickname: 'Mari').readyToSubmit, isTrue);
    });

    test('falso com igreja escolhida sem consentimento destacado (LGPD art. 11 I)', () {
      expect(_profile(churchId: 'igreja-1', churchConsent: false).readyToSubmit, isFalse);
    });

    test('verdadeiro com igreja escolhida e consentimento destacado aceito', () {
      expect(_profile(churchId: 'igreja-1', churchConsent: true).readyToSubmit, isTrue);
    });
  });

  group('Profile.toInsertMap', () {
    test('normaliza campos opcionais vazios para null', () {
      final map = _profile().toInsertMap(id: 'abc');
      expect(map['id'], 'abc');
      expect(map['apelido'], isNull);
      expect(map['telefone'], isNull);
      expect(map['genero'], 'feminino');
      expect(map['consentimento_lgpd_aceito_em'], isNotNull);
    });

    test('consentimento_lgpd_igreja_aceito_em é null sem igreja escolhida', () {
      final map = _profile().toInsertMap(id: 'abc');
      expect(map['consentimento_lgpd_igreja_aceito_em'], isNull);
    });

    test('consentimento_lgpd_igreja_aceito_em é preenchido com igreja + consentimento', () {
      final map = _profile(churchId: 'igreja-1', churchConsent: true).toInsertMap(id: 'abc');
      expect(map['igreja_id'], 'igreja-1');
      expect(map['consentimento_lgpd_igreja_aceito_em'], isNotNull);
    });
  });

  group('PublicProfile de um Perfil anonimizado (feature 009)', () {
    // Um Perfil anonimizado nunca é carregado num Profile — este é o único
    // caminho pelo qual o app enxerga quem excluiu a conta.
    test('exibe "Membro removido" e nenhuma Igreja', () {
      final publicProfile = PublicProfile.fromMap(const {
        'id': 'uid-que-saiu',
        'nome_exibido': 'Membro removido',
        'igreja_id': null,
      });

      expect(publicProfile.displayName, 'Membro removido');
      expect(publicProfile.churchId, isNull);
    });
  });
}

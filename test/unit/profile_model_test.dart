import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';

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

  group('Profile.fromMap — ler o próprio Perfil do banco (feature 016)', () {
    Map<String, dynamic> row({
      String? nickname = 'Aninha',
      String? churchId = 'igreja-1',
      String? phone = '81999990000',
      String? gender = 'feminino',
      int? age = 30,
      String? churchConsentAt = '2026-08-01T10:00:00.000Z',
    }) {
      return {
        'nome': 'Ana Souza',
        'apelido': nickname,
        'igreja_id': churchId,
        'telefone': phone,
        'genero': gender,
        'idade': age,
        'consentimento_lgpd_aceito_em': '2026-07-25T12:00:00.000Z',
        'consentimento_lgpd_igreja_aceito_em': churchConsentAt,
      };
    }

    test('lê as sete colunas pessoais e a data do consentimento', () {
      final profile = Profile.fromMap(row());

      expect(profile.name, 'Ana Souza');
      expect(profile.nickname, 'Aninha');
      expect(profile.churchId, 'igreja-1');
      expect(profile.phone, '81999990000');
      expect(profile.gender, Gender.female);
      expect(profile.age, 30);
      expect(profile.lgpdConsentAcceptedAt, isNotNull);
      // A coluna é `not null` no banco: linha que existe é linha que consentiu.
      expect(profile.lgpdConsentAccepted, isTrue);
      expect(profile.churchLgpdConsentAccepted, isTrue);
    });

    test('aceita idade e gênero nulos — é o Perfil anonimizado', () {
      // A feature 009 nulificou as duas colunas ao anonimizar. Ler sem cuidado
      // estouraria justamente na linha de quem já pediu para sumir.
      final profile = Profile.fromMap(row(gender: null, age: null));

      expect(profile.gender, isNull);
      expect(profile.age, isNull);
      expect(profile.isMinor, isFalse);
    });

    test('sem consentimento de Igreja, a data e o sinal ficam vazios', () {
      final profile = Profile.fromMap(row(churchId: null, churchConsentAt: null));

      expect(profile.churchLgpdConsentAccepted, isFalse);
      expect(profile.churchLgpdConsentAcceptedAt, isNull);
    });
  });

  group('Profile.toUpdateMap — as cinco colunas corrigíveis (feature 016)', () {
    Profile editable({
      String name = 'Ana Souza',
      String? nickname = 'Aninha',
      String? churchId,
      String? phone = '81999990000',
      DateTime? churchConsentAt,
    }) {
      return Profile(
        name: name,
        gender: Gender.female,
        age: 30,
        lgpdConsentAccepted: true,
        nickname: nickname,
        churchId: churchId,
        phone: phone,
        churchLgpdConsentAcceptedAt: churchConsentAt,
      );
    }

    test('tem exatamente cinco chaves, e nenhuma delas é intocável', () {
      final map = editable().toUpdateMap();

      expect(map.keys, hasLength(5));
      expect(map.keys, containsAll(<String>[
        'nome',
        'apelido',
        'igreja_id',
        'telefone',
        'consentimento_lgpd_igreja_aceito_em',
      ]));
      // Este é o teste que trava a decisão contra um "só mais um campinho"
      // futuro. Reusar toInsertMap num UPDATE reescreveria a data da base
      // legal a cada correção de telefone.
      for (final forbidden in <String>[
        'id',
        'idade',
        'genero',
        'consentimento_lgpd_aceito_em',
        'anonimizado_em',
      ]) {
        expect(map.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('Apelido e telefone vazios viram null, nunca string vazia', () {
      final map = editable(nickname: '   ', phone: '').toUpdateMap();

      // `apelido_obrigatorio_menor` checa `is not null`: uma string vazia
      // passaria pela constraint e deixaria um menor sem Apelido de verdade.
      expect(map['apelido'], isNull);
      expect(map['telefone'], isNull);
    });

    test('a data do consentimento de Igreja é a que vier no Profile', () {
      final at = DateTime.utc(2026, 8, 5, 9);
      final map =
          editable(churchId: 'igreja-1', churchConsentAt: at).toUpdateMap();

      expect(map['igreja_id'], 'igreja-1');
      expect(map['consentimento_lgpd_igreja_aceito_em'], at.toIso8601String());
    });

    test('sem Igreja, a data do consentimento destacado é zerada junto', () {
      final map = editable(churchId: null).toUpdateMap();

      expect(map['igreja_id'], isNull);
      expect(map['consentimento_lgpd_igreja_aceito_em'], isNull);
    });
  });
}

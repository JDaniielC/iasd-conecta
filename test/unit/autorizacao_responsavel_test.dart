import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/legal/legal_metadata.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';

/// Feature 015 — autorização do Responsável para cadastro de Criança.
///
/// Nenhum teste aqui usa idade literal. Todos derivam de `childAgeThreshold`,
/// para sobreviverem intactos se o limiar mudar — o número é decisão de
/// produto, e um teste que o repete vira um segundo lugar onde a decisão mora.
Profile buildChildProfile({
  String? guardianName = 'Maria Silva',
  String? guardianContact = 'maria@exemplo.com',
  bool guardianAuthorizationAccepted = true,
}) {
  return Profile(
    name: 'Ana Silva',
    gender: Gender.female,
    age: childAgeThreshold - 1,
    lgpdConsentAccepted: true,
    nickname: 'Aninha',
    guardianName: guardianName,
    guardianContact: guardianContact,
    guardianAuthorizationAccepted: guardianAuthorizationAccepted,
  );
}

Profile buildAdultProfile({
  String? guardianName,
  String? guardianContact,
}) {
  return Profile(
    name: 'Carla Souza',
    gender: Gender.female,
    age: 30,
    lgpdConsentAccepted: true,
    guardianName: guardianName,
    guardianContact: guardianContact,
  );
}

void main() {
  group('quem é Criança', () {
    test('um ano abaixo do limiar é Criança', () {
      expect(buildChildProfile().isChild, isTrue);
    });

    test('exatamente no limiar NÃO é Criança', () {
      // O limiar é exclusivo: `age < childAgeThreshold`. Quem tem exatamente a
      // idade do limiar é adolescente, e adolescente não exige autorização.
      final profile = Profile(
        name: 'Bia',
        gender: Gender.female,
        age: childAgeThreshold,
        lgpdConsentAccepted: true,
        nickname: 'Bi',
      );
      expect(profile.isChild, isFalse);
      expect(profile.needsGuardianAuthorization, isFalse);
    });

    test('Criança continua sendo menor de idade', () {
      // As duas proteções coexistem: Apelido obrigatório vem de isMinor, e
      // autorização vem de isChild.
      expect(buildChildProfile().isMinor, isTrue);
    });
  });

  group('readyToSubmit exige os três, não só a caixa', () {
    test('completo, com nome, contato e autorização, está pronto', () {
      expect(buildChildProfile().readyToSubmit, isTrue);
    });

    test('sem a autorização marcada, não está pronto', () {
      expect(
        buildChildProfile(guardianAuthorizationAccepted: false).readyToSubmit,
        isFalse,
      );
    });

    test('sem o nome do Responsável, não está pronto', () {
      expect(buildChildProfile(guardianName: '   ').readyToSubmit, isFalse);
    });

    test('sem o contato do Responsável, não está pronto', () {
      // Marcar a caixa sem dizer quem autorizou não demonstra nada, e o ônus
      // da prova do consentimento é do controlador.
      expect(buildChildProfile(guardianContact: null).readyToSubmit, isFalse);
    });

    test('adulto não precisa de nada disso', () {
      expect(buildAdultProfile().readyToSubmit, isTrue);
    });
  });

  group('toInsertMap', () {
    test('Criança grava nome, contato, data e versão', () {
      final map = buildChildProfile().toInsertMap(id: 'uid-1');

      expect(map['responsavel_nome'], 'Maria Silva');
      expect(map['responsavel_contato'], 'maria@exemplo.com');
      expect(map['autorizacao_responsavel_em'], isNotNull);
      // A versão é o que dá valor probatório junto com a data.
      expect(map['autorizacao_responsavel_versao'], LegalMetadata.version);
    });

    test('acima do limiar, as quatro vão nulas mesmo se preenchidas', () {
      // O caso real: o formulário mostrou os campos, a pessoa corrigiu a idade
      // para cima, e o estado ficou lá. A constraint
      // `autorizacao_responsavel_so_para_crianca` recusaria a linha.
      final map = buildAdultProfile(
        guardianName: 'Alguém',
        guardianContact: 'alguem@exemplo.com',
      ).toInsertMap(id: 'uid-2');

      expect(map['responsavel_nome'], isNull);
      expect(map['responsavel_contato'], isNull);
      expect(map['autorizacao_responsavel_em'], isNull);
      expect(map['autorizacao_responsavel_versao'], isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/legal/domain/consent_tally.dart';

void main() {
  group('ConsentKind', () {
    test('os valores do banco são o contrato, e estão em português', () {
      expect(ConsentKind.lgpd.dbValue, 'lgpd');
      expect(ConsentKind.church.dbValue, 'igreja');
      expect(ConsentKind.fromDbValue('igreja'), ConsentKind.church);
    });
  });

  group('ConsentTally.fromMap', () {
    test('lê as chaves em português que a função do banco devolve', () {
      final tally = ConsentTally.fromMap({
        'tipo': 'lgpd',
        'versao': '1.2',
        'quantidade': 7,
      });

      expect(tally.kind, ConsentKind.lgpd);
      expect(tally.consentedVersion, '1.2');
      expect(tally.count, 7);
      expect(tally.isVersionUnknown, isFalse);
    });

    test('versão nula é desconhecida, não zero nem vazio', () {
      final tally = ConsentTally.fromMap({
        'tipo': 'igreja',
        'versao': null,
        'quantidade': 3,
      });

      // A distinção é a feature: `null` quer dizer "não dá para saber qual
      // texto essa pessoa aceitou", e tratá-lo como ausência de dado apagaria
      // justamente o que FR-007 manda registrar.
      expect(tally.isVersionUnknown, isTrue);
      expect(tally.consentedVersion, isNull);
      expect(tally.count, 3);
    });
  });
}

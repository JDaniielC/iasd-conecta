import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_distrito_vsa/features/acao_sugerida/domain/suggested_action.dart';

void main() {
  group('SuggestedAction.fromMap', () {
    test('lê id, categoryId e name do map', () {
      final action = SuggestedAction.fromMap({
        'id': 's1',
        'categoria_id': 'c1',
        'nome': 'Ensaio',
      });
      expect(action.id, 's1');
      expect(action.categoryId, 'c1');
      expect(action.name, 'Ensaio');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/district_admin/domain/district_admin.dart';

void main() {
  group('DistrictAdmin.fromMap', () {
    test('parseia usuario_id/promovido_por/created_at corretamente', () {
      final admin = DistrictAdmin.fromMap({
        'usuario_id': 'u1',
        'promovido_por': 'u2',
        'created_at': '2026-07-24T10:00:00.000Z',
      });

      expect(admin.userId, 'u1');
      expect(admin.promotedBy, 'u2');
      expect(admin.createdAt, DateTime.parse('2026-07-24T10:00:00.000Z'));
    });
  });
}

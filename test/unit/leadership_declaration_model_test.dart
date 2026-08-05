import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';

LeadershipDeclaration _declaration({DateTime? confirmedAt, DateTime? rejectedAt, int year = 2026}) {
  return LeadershipDeclaration(
    id: 'l1',
    groupId: 'g1',
    userId: 'u1',
    year: year,
    declaredAt: DateTime(2026, 1, 1),
    confirmedAt: confirmedAt,
    rejectedAt: rejectedAt,
  );
}

void main() {
  group('LeadershipDeclaration.status', () {
    test('pending quando nem confirmado nem rejeitado', () {
      expect(_declaration().status, LeadershipStatus.pending);
    });

    test('confirmed quando confirmedAt preenchido', () {
      expect(_declaration(confirmedAt: DateTime(2026, 2, 1)).status, LeadershipStatus.confirmed);
    });

    test('rejected quando rejectedAt preenchido', () {
      expect(_declaration(rejectedAt: DateTime(2026, 2, 1)).status, LeadershipStatus.rejected);
    });
  });

  group('LeadershipDeclaration.isCurrentFor', () {
    test('verdadeiro só se confirmada e do ano informado', () {
      final declaration = _declaration(confirmedAt: DateTime(2026, 2, 1), year: 2026);
      expect(declaration.isCurrentFor(2026), isTrue);
    });

    test('falso se confirmada mas de outro ano (FR-008)', () {
      final declaration = _declaration(confirmedAt: DateTime(2025, 2, 1), year: 2025);
      expect(declaration.isCurrentFor(2026), isFalse);
    });

    test('falso se pendente, mesmo no ano informado', () {
      final declaration = _declaration(year: 2026);
      expect(declaration.isCurrentFor(2026), isFalse);
    });
  });
}

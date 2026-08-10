import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/district_admin/data/district_admin_repository.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/district_admin/presentation/manage_churches_page.dart';
import 'package:iasd_conecta/features/profile/data/profile_repository.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';
import 'package:mocktail/mocktail.dart';

class MockDistrictAdminRepository extends Mock implements DistrictAdminRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

final _churches = [
  const Church(id: 'c1', name: 'Igreja Ativa'),
  Church(id: 'c2', name: 'Igreja Arquivada', archivedAt: DateTime(2026, 1, 1)),
];

void main() {
  testWidgets(
    'ManageChurchesPage lista ativas e arquivadas, com botão Arquivar só nas ativas',
    (tester) async {
      final profileRepo = MockProfileRepository();
      when(() => profileRepo.fetchChurches()).thenAnswer((_) async => _churches);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileRepositoryProvider.overrideWithValue(profileRepo),
            districtAdminRepositoryProvider.overrideWithValue(MockDistrictAdminRepository()),
          ],
          child: const MaterialApp(home: ManageChurchesPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Igreja Ativa'), findsOneWidget);
      expect(find.text('Igreja Arquivada'), findsOneWidget);
      expect(find.text('Arquivada'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Arquivar'), findsOneWidget);
    },
  );
}

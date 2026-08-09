import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/group_list_page.dart';
import 'package:iasd_conecta/features/profile/data/auth_repository.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GroupRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

const _churches = [
  Church(id: 'igreja-1', name: 'Central'),
  Church(id: 'igreja-2', name: 'Pombos'),
];

final _grupos = [
  Group(
    id: 'g1',
    nome: 'SevenBikers',
    categoria: 'Ministério Jovem',
    igrejaId: 'igreja-1',
    donoId: 'dono-1',
    createdAt: DateTime(2026, 1, 1),
  ),
  Group(
    id: 'g2',
    nome: 'Coral',
    categoria: 'Ministério da Música',
    igrejaId: 'igreja-2',
    donoId: 'dono-2',
    createdAt: DateTime(2026, 1, 2),
  ),
];

Future<void> _pump(WidgetTester tester, {required bool hasPerfil}) async {
  final grupoRepo = MockGrupoRepository();
  when(() => grupoRepo.fetchGroups()).thenAnswer((_) async => _grupos);
  final authRepo = MockAuthRepository();
  when(() => authRepo.temConta).thenReturn(false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasPerfilProvider.overrideWith((ref) async => hasPerfil),
        groupRepositoryProvider.overrideWithValue(grupoRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
        churchesProvider.overrideWith((ref) async => _churches),
      ],
      child: const MaterialApp(home: GroupListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR-005: lista de Grupos aparece sem exigir Perfil', (tester) async {
    await _pump(tester, hasPerfil: false);

    expect(find.text('SevenBikers'), findsOneWidget);
    expect(find.text('Coral'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsOneWidget);
  });

  testWidgets('sem o banner de CTA quando já tem Perfil', (tester) async {
    await _pump(tester, hasPerfil: true);

    expect(find.text('SevenBikers'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsNothing);
  });

  testWidgets('agrupa os Grupos por Igreja com cabeçalho de seção', (tester) async {
    await _pump(tester, hasPerfil: false);

    expect(find.text('Central'), findsOneWidget);
    expect(find.text('Pombos'), findsOneWidget);
  });
}

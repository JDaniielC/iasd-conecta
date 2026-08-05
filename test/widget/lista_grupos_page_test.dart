import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/grupo/data/grupo_repository.dart';
import 'package:iasd_conecta/features/grupo/domain/grupo.dart';
import 'package:iasd_conecta/features/grupo/grupo_providers.dart';
import 'package:iasd_conecta/features/grupo/presentation/lista_grupos_page.dart';
import 'package:iasd_conecta/features/perfil/data/auth_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GrupoRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

const _grupos = [
  Grupo(
    id: 'g1',
    nome: 'SevenBikers',
    categoria: 'Ministério Jovem',
    horario: 'sábados 6h',
    local: 'Praça Central',
    donoId: 'dono-1',
  ),
  Grupo(
    id: 'g2',
    nome: 'Coral',
    categoria: 'Ministério da Música',
    horario: 'quartas 19h',
    local: 'Sede',
    donoId: 'dono-2',
  ),
];

Future<void> _pump(WidgetTester tester, {required bool hasPerfil}) async {
  final grupoRepo = MockGrupoRepository();
  when(() => grupoRepo.fetchGrupos()).thenAnswer((_) async => _grupos);
  final authRepo = MockAuthRepository();
  when(() => authRepo.temConta).thenReturn(false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasPerfilProvider.overrideWith((ref) async => hasPerfil),
        grupoRepositoryProvider.overrideWithValue(grupoRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
      ],
      child: const MaterialApp(home: ListaGruposPage()),
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
}

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

class MockGroupRepository extends Mock implements GroupRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

const _churches = [
  Church(id: 'igreja-1', name: 'Central'),
  Church(id: 'igreja-2', name: 'Pombos'),
];

final _groups = [
  Group(
    id: 'g1',
    name: 'SevenBikers',
    category: 'Ministério Jovem',
    churchId: 'igreja-1',
    ownerId: 'dono-1',
    createdAt: DateTime(2026, 1, 1),
  ),
  Group(
    id: 'g2',
    name: 'Coral',
    category: 'Ministério da Música',
    churchId: 'igreja-2',
    ownerId: 'dono-2',
    createdAt: DateTime(2026, 1, 2),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool hasProfile,
  Object? fetchThrows,
}) async {
  final groupRepo = MockGroupRepository();
  if (fetchThrows != null) {
    when(
      () => groupRepo.fetchGroups(),
    ).thenAnswer((_) async => throw fetchThrows);
  } else {
    when(() => groupRepo.fetchGroups()).thenAnswer((_) async => _groups);
  }
  final authRepo = MockAuthRepository();
  when(() => authRepo.hasAccount).thenReturn(false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => hasProfile),
        groupRepositoryProvider.overrideWithValue(groupRepo),
        authRepositoryProvider.overrideWithValue(authRepo),
        churchesProvider.overrideWith((ref) async => _churches),
      ],
      child: const MaterialApp(home: GroupListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a consulta recusada DIZ que não deu, e não "nenhum Grupo"', (
    tester,
  ) async {
    // O caminho degradado da change `fechar-superficie-anon`, e é o único em
    // que o app fala com o banco sem sessão: `signInAnonymously` falhou no
    // arranque, e `anon` já não tem `grant select` em `grupos`.
    //
    // Antes daquela change `anon` LIA `grupos`, e esta tela mostrava a lista.
    // Agora recebe `42501`, e a diferença entre os dois desfechos é o que este
    // teste segura: "Nenhum Grupo ainda." afirmaria que o distrito não tem
    // Grupo nenhum, que é falso e é a mentira por omissão que a spec
    // `superficie-sem-login` proíbe.
    //
    // Verificado à mão em 2026-08-16 com o app rodando e o login anônimo
    // recusado (422): a tela mostra a frase de erro, com 1 Grupo no banco.
    // Este teste existe porque aquilo foi uma execução única — quem trocar o
    // ramo `error:` por um `SizedBox` faz a tela voltar a mentir e nenhum gate
    // acusa.
    await _pump(
      tester,
      hasProfile: false,
      fetchThrows: StateError('permission denied for table grupos'),
    );

    expect(find.text('Não deu pra carregar os Grupos agora.'), findsOneWidget);
    expect(
      find.text('Nenhum Grupo ainda.'),
      findsNothing,
      reason:
          'recusa não é ausência — dizer "nenhum" seria afirmar sobre o '
          'distrito uma coisa que não se sabe',
    );
  });

  testWidgets('FR-005: lista de Grupos aparece sem exigir Perfil', (
    tester,
  ) async {
    await _pump(tester, hasProfile: false);

    expect(find.text('SevenBikers'), findsOneWidget);
    expect(find.text('Coral'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsOneWidget);
  });

  testWidgets('sem o banner de CTA quando já tem Perfil', (tester) async {
    await _pump(tester, hasProfile: true);

    expect(find.text('SevenBikers'), findsOneWidget);
    expect(find.text('Criar Perfil'), findsNothing);
  });

  testWidgets('agrupa os Grupos por Igreja com cabeçalho de seção', (
    tester,
  ) async {
    await _pump(tester, hasProfile: false);

    expect(find.text('Central'), findsOneWidget);
    expect(find.text('Pombos'), findsOneWidget);
  });
}

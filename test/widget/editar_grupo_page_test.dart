import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/grupo/data/grupo_repository.dart';
import 'package:iasd_conecta/features/grupo/domain/grupo.dart';
import 'package:iasd_conecta/features/grupo/grupo_providers.dart';
import 'package:iasd_conecta/features/grupo/presentation/editar_grupo_page.dart';
import 'package:iasd_conecta/features/perfil/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

class MockGrupoRepository extends Mock implements GrupoRepository {}

final _grupo = Grupo(
  id: 'g1',
  nome: 'SevenBikers',
  categoria: 'Ministério Jovem',
  horario: 'sábados 6h',
  local: 'Praça Central',
  donoId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

Future<void> _pump(WidgetTester tester, {required String? uid}) async {
  final grupoRepo = MockGrupoRepository();
  when(() => grupoRepo.fetchGrupo('g1')).thenAnswer((_) async => _grupo);
  when(() => grupoRepo.fetchParticipantes('g1')).thenAnswer(
    (_) async => const [PublicProfile(id: 'dono-1', displayName: 'Dono')],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(uid),
        grupoRepositoryProvider.overrideWithValue(grupoRepo),
      ],
      child: const MaterialApp(home: EditarGrupoPage(grupoId: 'g1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR-009: quem não é Dono vê aviso e não vê o formulário', (tester) async {
    await _pump(tester, uid: 'nao-e-o-dono');

    expect(find.text('Você não é o Dono deste Grupo.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Nome'), findsNothing);
  });

  testWidgets('Dono vê o formulário preenchido com os dados do Grupo', (tester) async {
    await _pump(tester, uid: 'dono-1');

    expect(find.text('Você não é o Dono deste Grupo.'), findsNothing);
    final campoNome = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nome'));
    expect(campoNome.controller?.text, 'SevenBikers');
  });
}

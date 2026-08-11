import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/cover_photo/cover_photo_providers.dart';
import 'package:iasd_conecta/features/cover_photo/data/cover_photo_repository.dart';
import 'package:iasd_conecta/features/cover_photo/domain/cover_photo.dart';
import 'package:mocktail/mocktail.dart';

class MockCoverPhotoRepository extends Mock implements CoverPhotoRepository {}

/// **Uma consulta por listagem, não uma por quadro.**
///
/// Este arquivo existe por causa de um laço de rede medido. A consulta em lote
/// nasceu como conserto — evitar que o card crescesse quando a capa chegasse
/// (FR-007) — e trocou um pulo de layout por algo pior.
///
/// A causa: a chave da família era uma `List<String>`, e `List` não implementa
/// `==` por valor. Como as telas montam a lista dentro do `build`, cada quadro
/// criava um provider **novo**, que consultava, que completava, que
/// reconstruía. Medido nesta mesma réplica: **31 consultas em 30 quadros**.
///
/// A chave passou a ser `String`, que tem igualdade por valor — e **ordenada**,
/// para que trocar a ordenação da lista não conte como outra lista.
class _ListReplica extends ConsumerWidget {
  const _ListReplica({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lista nova a cada build, exatamente como em group_list_page.dart.
    final key = coverPhotosKey([...ids]);
    final covers = ref.watch(groupCoverPhotosProvider(key)).value ??
        const <String, CoverPhoto>{};
    return Text('${covers.length}', textDirection: TextDirection.ltr);
  }
}

void main() {
  late MockCoverPhotoRepository repository;
  late int calls;

  setUp(() {
    calls = 0;
    repository = MockCoverPhotoRepository();
    when(() => repository.fetchForGroups(any())).thenAnswer((_) async {
      calls++;
      return <String, CoverPhoto>{};
    });
  });

  Future<void> pumpFrames(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [coverPhotoRepositoryProvider.overrideWithValue(repository)],
      child: child,
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('30 quadros, 1 consulta', (tester) async {
    await pumpFrames(tester, const _ListReplica(ids: ['g1', 'g2']));
    expect(calls, 1,
        reason: 'consulta por quadro é laço de rede, não carregamento');
  });

  testWidgets('a mesma lista em ordem diferente é a mesma consulta',
      (tester) async {
    // A listagem de Grupos tem alternador de ordenação. Sem ordenar a chave,
    // trocar a ordem refaria a consulta inteira por nada — os Grupos são os
    // mesmos.
    expect(
      coverPhotosKey(['g2', 'g1']),
      coverPhotosKey(['g1', 'g2']),
    );
    await pumpFrames(tester, const _ListReplica(ids: ['g2', 'g1']));
    expect(calls, 1);
  });

  testWidgets('lista vazia também não entra em laço', (tester) async {
    await pumpFrames(tester, const _ListReplica(ids: []));
    // Uma chamada, não trinta. O servidor não é tocado nenhuma vez: quem
    // corta é a guarda de lista vazia dentro de `fetchForGroups`, não este
    // provider — por isso o contador aqui é 1 e não 0.
    expect(calls, 1);
    final captured =
        verify(() => repository.fetchForGroups(captureAny())).captured;
    expect(captured.single, isEmpty);
  });

  testWidgets('lista diferente consulta de novo', (tester) async {
    await pumpFrames(tester, const _ListReplica(ids: ['g1']));
    expect(calls, 1);
    await pumpFrames(tester, const _ListReplica(ids: ['g1', 'g2']));
    expect(calls, 2, reason: 'Grupo novo na tela precisa da capa dele');
  });

  testWidgets(
    'FR-012: invalidar a família refaz a consulta da listagem — é o que faz a '
    'imagem removida sumir da lista',
    (tester) async {
      late WidgetRef captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          coverPhotoRepositoryProvider.overrideWithValue(repository),
        ],
        child: Consumer(builder: (context, ref, _) {
          captured = ref;
          final key = coverPhotosKey(['g1']);
          ref.watch(groupCoverPhotosProvider(key));
          return const SizedBox.shrink();
        }),
      ));
      await tester.pumpAndSettle();
      expect(calls, 1);

      // O que `_invalidatePhoto` e o `_resolve` da tela de denúncias fazem
      // depois de remover uma capa. Sem isto, a rota de baixo continua
      // montada, o provider autoDispose mantém o valor, e a listagem segue
      // exibindo a imagem que já não existe.
      captured.invalidate(groupCoverPhotosProvider);
      await tester.pumpAndSettle();

      expect(calls, 2);
    },
  );
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/image_upload.dart';
import 'package:iasd_conecta/features/cover_photo/cover_photo_providers.dart';
import 'package:iasd_conecta/features/cover_photo/data/cover_photo_repository.dart';
import 'package:iasd_conecta/features/cover_photo/domain/cover_photo.dart';
import 'package:mocktail/mocktail.dart';

import 'package:iasd_conecta/features/cover_photo/presentation/cover_photo_widget.dart';

/// FR-031/FR-032 — **o que a pessoa lê quando o envio para no meio.**
///
/// Este arquivo existe por causa de uma constatação incômoda: seis rodadas de
/// convergência, 209 testes de integração, e **nenhum** deles fazia uma etapa
/// falhar no meio de uma sequência de escritas. O caminho feliz estava coberto
/// por todos os lados; o caminho de falha, por ninguém.
///
/// As três etapas do envio deixam estados diferentes quando falham, e até a
/// clarificação de 2026-08-10 as três recebiam a mesma frase — inclusive
/// aquela em que a capa que existia acabara de ser destruída. Dizer "nada foi
/// alterado" ali é informar o contrário do que aconteceu.
class MockCoverPhotoRepository extends Mock implements CoverPhotoRepository {}

class _FakeImageUpload implements ImageUpload {
  @override
  Future<PickedImage?> pick({
    required int maxBytes,
    required Set<String> allowedMimeTypes,
  }) async => PickedImage(
    bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]),
    mimeType: 'image/jpeg',
  );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CoverPhoto buildCover() => CoverPhoto(
  id: 'capa-1',
  groupId: 'grupo-1',
  path: 'grupo/grupo-1/x.jpg',
  uploadedBy: 'usuario-1',
  createdAt: DateTime.utc(2026, 8, 10),
);

/// Monta o editor com uma capa existente e um repositório que **falha na etapa
/// pedida**, depois percorre aviso → seletor → falha.
Future<MockCoverPhotoRepository> failAt(
  WidgetTester tester,
  CoverPhotoUploadFailed failure, {
  CoverPhoto? existing,
}) async {
  final repository = MockCoverPhotoRepository();
  when(
    () => repository.publicUrlFor(any()),
  ).thenReturn('http://127.0.0.1/inexistente.jpg');
  when(() => repository.requestDrain()).thenAnswer((_) async {});
  when(
    () => repository.uploadForGroup(
      groupId: any(named: 'groupId'),
      image: any(named: 'image'),
    ),
  ).thenThrow(failure);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coverPhotoRepositoryProvider.overrideWithValue(repository),
        imageUploadProvider.overrideWithValue(_FakeImageUpload()),
        groupCoverPhotoProvider(
          'grupo-1',
        ).overrideWith((ref) async => existing),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: CoverPhotoEditor(
            groupId: 'grupo-1',
            canUpload: true,
            canRemove: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(
    find.text(existing == null ? 'Adicionar capa' : 'Trocar capa'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Escolher imagem'));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(() {
    registerFallbackValue(buildCover());
    registerFallbackValue(
      PickedImage(bytes: Uint8List(0), mimeType: 'image/jpeg'),
    );
  });

  testWidgets(
    '(a) falha ao subir o arquivo: nada mudou, e a frase pode dizer isso',
    (tester) async {
      await failAt(
        tester,
        const CoverPhotoUploadFailed(CoverPhotoUploadStage.sendingFile),
        existing: buildCover(),
      );

      expect(
        find.text('Não deu pra enviar a imagem. Nada foi alterado.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '(b) falha ao tirar a linha antiga: a capa atual continua, e a frase não '
    'assusta',
    (tester) async {
      await failAt(
        tester,
        const CoverPhotoUploadFailed(CoverPhotoUploadStage.removingPrevious),
        existing: buildCover(),
      );

      // O arquivo novo ficou órfão no bucket, mas isso não é assunto de quem
      // está na tela: ninguém o vê e ninguém o refaz. A varredura recolhe em
      // até 24 horas (FR-033, SC-010).
      expect(
        find.text('Não deu pra trocar a capa. Nada foi alterado.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '(c) falha ao gravar a linha COM capa anterior: a frase diz que a capa '
    'foi perdida',
    (tester) async {
      await failAt(
        tester,
        const CoverPhotoUploadFailed(
          CoverPhotoUploadStage.savingRecord,
          previousPhotoLost: true,
        ),
        existing: buildCover(),
      );

      // É o caso que motivou a clarificação: a capa que existia deixou de
      // existir. Dizer "tente de novo" aqui, e só isso, é negar o que
      // aconteceu.
      expect(
        find.textContaining(
          'A capa anterior saiu do ar e a nova não foi '
          'salva.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('O Grupo está sem capa agora'),
        findsOneWidget,
      );
      expect(find.textContaining('Nada foi alterado'), findsNothing);
    },
  );

  testWidgets(
    '(d) falha ao gravar a linha SEM capa anterior: nada se perdeu, e a frase '
    'é outra',
    (tester) async {
      await failAt(
        tester,
        const CoverPhotoUploadFailed(CoverPhotoUploadStage.savingRecord),
      );

      expect(find.textContaining('O Grupo continua sem capa'), findsOneWidget);
      expect(find.textContaining('saiu do ar'), findsNothing);
    },
  );

  testWidgets(
    '(e) FR-031: no erro, a tela é atualizada — não fica mostrando o que já '
    'não existe',
    (tester) async {
      var reads = 0;
      final repository = MockCoverPhotoRepository();
      when(
        () => repository.publicUrlFor(any()),
      ).thenReturn('http://127.0.0.1/inexistente.jpg');
      when(() => repository.requestDrain()).thenAnswer((_) async {});
      when(
        () => repository.uploadForGroup(
          groupId: any(named: 'groupId'),
          image: any(named: 'image'),
        ),
      ).thenThrow(
        const CoverPhotoUploadFailed(
          CoverPhotoUploadStage.savingRecord,
          previousPhotoLost: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            imageUploadProvider.overrideWithValue(_FakeImageUpload()),
            groupCoverPhotoProvider('grupo-1').overrideWith((ref) async {
              reads++;
              // Na segunda leitura o banco já não tem capa: é o estado real
              // depois da falha.
              return reads == 1 ? buildCover() : null;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CoverPhotoEditor(
                groupId: 'grupo-1',
                canUpload: true,
                canRemove: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);

      await tester.tap(find.text('Trocar capa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Escolher imagem'));
      await tester.pumpAndSettle();

      // A segunda leitura só acontece se o caminho de erro invalidar o
      // provider. Sem isso a tela seguiria exibindo a capa destruída, e a
      // pessoa teria a prova visual de que nada aconteceu.
      expect(reads, 2);
      // E a capa some de fato: o botão volta a ser o de adicionar.
      expect(find.text('Adicionar capa'), findsOneWidget);
    },
  );

  testWidgets(
    '(f) FR-031 na REMOÇÃO: o erro atualiza a tela e a frase admite a dúvida',
    (tester) async {
      var reads = 0;
      final repository = MockCoverPhotoRepository();
      when(
        () => repository.publicUrlFor(any()),
      ).thenReturn('http://127.0.0.1/inexistente.jpg');
      when(() => repository.requestDrain()).thenAnswer((_) async {});
      // O erro típico aqui é tempo esgotado de rede: o servidor pode ter
      // removido e a resposta ter se perdido. O cliente NÃO SABE.
      when(() => repository.remove(any())).thenThrow(Exception('timeout'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            imageUploadProvider.overrideWithValue(_FakeImageUpload()),
            groupCoverPhotoProvider('grupo-1').overrideWith((ref) async {
              reads++;
              // Segunda leitura: o servidor tinha removido mesmo.
              return reads == 1 ? buildCover() : null;
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CoverPhotoEditor(
                groupId: 'grupo-1',
                canUpload: true,
                canRemove: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 1);

      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();

      expect(
        reads,
        2,
        reason:
            'sem reler, a tela seguiria mostrando uma '
            'imagem que já saiu do ar',
      );
      expect(find.text('Adicionar capa'), findsOneWidget);
      // A frase não afirma que nada aconteceu — porque pode ter acontecido.
      expect(
        find.textContaining('Não deu pra confirmar a remoção'),
        findsOneWidget,
      );
    },
  );
}

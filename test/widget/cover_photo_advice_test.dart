import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/cover_photo/cover_photo_providers.dart';
import 'package:iasd_conecta/features/cover_photo/data/cover_photo_repository.dart';
import 'package:iasd_conecta/features/cover_photo/domain/cover_photo.dart';
import 'package:iasd_conecta/features/cover_photo/presentation/cover_photo_advice_sheet.dart';
import 'package:iasd_conecta/features/cover_photo/presentation/cover_photo_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockCoverPhotoRepository extends Mock implements CoverPhotoRepository {}

CoverPhoto buildGroupCover({String groupId = 'grupo-1'}) => CoverPhoto(
      id: 'capa-1',
      groupId: groupId,
      path: 'grupo/$groupId/x.jpg',
      uploadedBy: 'usuario-1',
      createdAt: DateTime.utc(2026, 8, 10),
    );

Future<void> pumpEditor(
  WidgetTester tester, {
  required bool canManage,
  CoverPhoto? cover,
  String groupId = 'grupo-1',
}) async {
  final repository = MockCoverPhotoRepository();
  when(() => repository.publicUrlFor(any()))
      .thenReturn('http://127.0.0.1/inexistente.jpg');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coverPhotoRepositoryProvider.overrideWithValue(repository),
        groupCoverPhotoProvider(groupId).overrideWith((ref) async => cover),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CoverPhotoEditor(groupId: groupId, canManage: canManage),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(buildGroupCover());
  });

  group('FR-004/FR-005: o aviso é parada obrigatória antes do seletor', () {
    testWidgets('(a) aparece ANTES de qualquer seletor de arquivo, sem capa',
        (tester) async {
      await pumpEditor(tester, canManage: true);

      await tester.tap(find.text('Adicionar capa'));
      await tester.pumpAndSettle();

      // O aviso está na tela. O seletor de arquivo só é chamado depois de
      // "Escolher imagem" — se ele abrisse antes, este teste veria o aviso
      // ausente e a pergunta "esta imagem tem gente nela?" chegaria tarde
      // demais, porque a pessoa já teria escolhido.
      expect(find.byType(CoverPhotoAdviceSheet), findsOneWidget);
      expect(find.text('Use uma imagem ilustrativa'), findsOneWidget);
      expect(
        find.textContaining('nunca de crianças ou adolescentes'),
        findsOneWidget,
      );
      // O motivo verdadeiro, não apelo jurídico.
      expect(
        find.textContaining('qualquer pessoa na internet'),
        findsOneWidget,
      );
    });

    testWidgets('(b) aparece DE NOVO na troca de uma capa que já existe',
        (tester) async {
      await pumpEditor(tester, canManage: true, cover: buildGroupCover());

      expect(find.text('Trocar capa'), findsOneWidget);
      await tester.tap(find.text('Trocar capa'));
      await tester.pumpAndSettle();

      expect(find.byType(CoverPhotoAdviceSheet), findsOneWidget);
    });

    testWidgets('não oferece "não mostrar de novo"', (tester) async {
      await pumpEditor(tester, canManage: true);
      await tester.tap(find.text('Adicionar capa'));
      await tester.pumpAndSettle();

      // Transformaria a barreira em nada depois do primeiro uso — e quem
      // envia muitas imagens é quem mais precisa vê-la (research D-005).
      expect(find.textContaining('não mostrar'), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('cancelar fecha o aviso e não abre seletor nenhum',
        (tester) async {
      await pumpEditor(tester, canManage: true);
      await tester.tap(find.text('Adicionar capa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(CoverPhotoAdviceSheet), findsNothing);
    });
  });

  group('FR-003: quem não administra não encontra opção de capa', () {
    testWidgets('(c) Usuário comum não vê nenhuma ação, mesmo com capa',
        (tester) async {
      await pumpEditor(tester, canManage: false, cover: buildGroupCover());

      expect(find.text('Adicionar capa'), findsNothing);
      expect(find.text('Trocar capa'), findsNothing);
      expect(find.text('Remover capa'), findsNothing);
      // Mas vê a capa: ela é pública (FR-008).
      expect(find.byType(CoverPhotoView), findsOneWidget);
    });

    testWidgets('Usuário comum não vê ação nenhuma em Grupo sem capa',
        (tester) async {
      await pumpEditor(tester, canManage: false);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('FR-002: ausência de capa não deixa buraco', () {
    testWidgets('sem capa, a exibição ocupa zero', (tester) async {
      await pumpEditor(tester, canManage: false);

      // Nada de moldura vazia nem de ícone de "sem foto". A maioria dos
      // Grupos não vai ter capa, e um retângulo cinza repetido na lista
      // inteira é pior do que nada.
      expect(find.byType(AspectRatio), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('com capa, o espaço é reservado com proporção fixa',
        (tester) async {
      await pumpEditor(tester, canManage: false, cover: buildGroupCover());

      final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
      // Proporção FIXA, não derivada da imagem: derivar exigiria conhecer a
      // imagem, o que só acontece depois de baixá-la — que é exatamente o
      // momento em que a lista não pode pular (FR-007).
      expect(aspect.aspectRatio, CoverPhotoView.aspectRatio);
    });
  });

  group('FR-010/SC-009: falha de envio não altera nada', () {
    testWidgets('remoção que falha mantém a capa e avisa', (tester) async {
      final repository = MockCoverPhotoRepository();
      when(() => repository.publicUrlFor(any()))
          .thenReturn('http://127.0.0.1/inexistente.jpg');
      when(() => repository.remove(any()))
          .thenThrow(Exception('rede caiu no meio'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            groupCoverPhotoProvider('grupo-1')
                .overrideWith((ref) async => buildGroupCover()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: CoverPhotoEditor(groupId: 'grupo-1', canManage: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();

      // A falha vira aviso, não exceção vermelha nem tela em branco.
      expect(find.textContaining('Não deu pra remover'), findsOneWidget);
      // E a capa continua lá: nada foi alterado no Grupo.
      expect(find.byType(CoverPhotoView), findsOneWidget);
      expect(find.text('Trocar capa'), findsOneWidget);
    });
  });
}

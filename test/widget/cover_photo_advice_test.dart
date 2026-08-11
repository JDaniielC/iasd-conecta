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
  bool? canUpload,
  bool? canRemove,
  CoverPhoto? cover,
  String groupId = 'grupo-1',
}) async {
  final repository = MockCoverPhotoRepository();
  when(() => repository.publicUrlFor(any()))
      .thenReturn('http://127.0.0.1/inexistente.jpg');
  when(() => repository.requestDrain()).thenAnswer((_) async {});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coverPhotoRepositoryProvider.overrideWithValue(repository),
        groupCoverPhotoProvider(groupId).overrideWith((ref) async => cover),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CoverPhotoEditor(
            groupId: groupId,
            canUpload: canUpload ?? canManage,
            canRemove: canRemove ?? canManage,
          ),
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
      // FR-009 / research D-002: o limite é informado ANTES do envio, e não
      // descoberto no erro depois de esperar o upload.
      expect(find.textContaining('Até 5 MB'), findsOneWidget);
      expect(find.textContaining('JPG, PNG ou WEBP'), findsOneWidget);
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
      when(() => repository.requestDrain()).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            groupCoverPhotoProvider('grupo-1')
                .overrideWith((ref) async => buildGroupCover()),
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

      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();

      // A falha vira aviso, não exceção vermelha nem tela em branco.
      //
      // A frase mudou em 2026-08-10 por FR-031: a antiga era "Não deu pra
      // remover a imagem agora. Tente de novo.", que **afirma** que a remoção
      // não aconteceu. Num tempo esgotado de rede o cliente não sabe disso —
      // o servidor pode ter removido e a resposta ter se perdido. A frase de
      // hoje admite a dúvida e manda conferir a tela, que foi relida.
      expect(
        find.textContaining('Não deu pra confirmar a remoção'),
        findsOneWidget,
      );
      // E a capa continua lá: a releitura devolveu a mesma capa, então neste
      // caso a remoção realmente não aconteceu.
      expect(find.byType(CoverPhotoView), findsOneWidget);
      expect(find.text('Trocar capa'), findsOneWidget);
    });
  });

  group('FR-011: o Administrador do distrito tira do ar o que não é dele', () {
    // A regra de quem administra é decidida pelas telas (Grupo: dono; Ação:
    // criador; e o Administrador do distrito nos dois), e o banco é quem
    // garante — `fotos_capa_delete_admin`. Aqui se prova o que a pessoa VÊ.
    testWidgets('vê remover em Grupo alheio, com a capa na tela',
        (tester) async {
      await pumpEditor(tester, canManage: true, cover: buildGroupCover());

      // SC-003: da tela onde a imagem aparece até a remoção, em até 3 toques.
      // Aqui é um.
      expect(find.text('Remover capa'), findsOneWidget);
    });

    testWidgets('Usuário comum em Grupo alheio não vê remover', (tester) async {
      await pumpEditor(tester, canManage: false, cover: buildGroupCover());
      expect(find.text('Remover capa'), findsNothing);
    });

    testWidgets('FR-014: depois de remover, pode enviar outra', (tester) async {
      // Sem capa e podendo administrar, a ação oferecida é "Adicionar capa" —
      // remover não é uma porta de mão única.
      await pumpEditor(tester, canManage: true);
      expect(find.text('Adicionar capa'), findsOneWidget);
      expect(find.text('Remover capa'), findsNothing);
    });
  });

  group('FR-011: o Administrador alcança o que é histórico', () {
    // A regra de "não mexer em histórico" é do Dono e do criador, não do
    // Administrador do distrito. Ação encerrada MANTÉM a capa (FR-023); se o
    // Administrador não a alcançasse pela tela, a única saída seria a lista de
    // denúncias — e só se alguém denunciasse.
    testWidgets('remove capa mesmo quando o dono já não pode', (tester) async {
      await pumpEditor(tester, canManage: true, cover: buildGroupCover());
      expect(find.text('Remover capa'), findsOneWidget);
    });
  });

  group('FR-011/FR-022: enviar e remover são permissões separadas', () {
    // Quando eram uma só, dar ao Administrador o poder de remover no histórico
    // deu junto o poder de PUBLICAR ali. Numa Ação já cancelada isso é pior do
    // que parece: o gatilho de cancelamento só dispara na transição, então a
    // capa enviada depois não sairia por caminho nenhum.
    testWidgets('no histórico: remove, mas não envia', (tester) async {
      await pumpEditor(
        tester,
        canManage: false,
        canUpload: false,
        canRemove: true,
        cover: buildGroupCover(),
      );

      expect(find.text('Remover capa'), findsOneWidget);
      expect(find.text('Trocar capa'), findsNothing);
      expect(find.text('Adicionar capa'), findsNothing);
    });

    testWidgets('no histórico e sem capa: nenhuma ação aparece',
        (tester) async {
      await pumpEditor(
        tester,
        canManage: false,
        canUpload: false,
        canRemove: true,
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('a fila é cutucada depois de mexer nela', () {
    // pg_cron roda dentro do Postgres, e projeto no plano gratuito é pausado
    // depois de uma semana sem atividade — com o banco pausado o cron para
    // junto. Quem acorda o banco é o app, então é o app que pede a drenagem.
    testWidgets('remover pede a drenagem', (tester) async {
      final repository = MockCoverPhotoRepository();
      when(() => repository.publicUrlFor(any()))
          .thenReturn('http://127.0.0.1/inexistente.jpg');
      when(() => repository.remove(any())).thenAnswer((_) async {});
      when(() => repository.requestDrain()).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            groupCoverPhotoProvider('grupo-1')
                .overrideWith((ref) async => buildGroupCover()),
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

      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();

      verify(() => repository.requestDrain()).called(1);
    });

    testWidgets('remoção que falha NÃO pede a drenagem — não há o que drenar',
        (tester) async {
      final repository = MockCoverPhotoRepository();
      when(() => repository.publicUrlFor(any()))
          .thenReturn('http://127.0.0.1/inexistente.jpg');
      when(() => repository.remove(any())).thenThrow(Exception('rede'));
      when(() => repository.requestDrain()).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coverPhotoRepositoryProvider.overrideWithValue(repository),
            groupCoverPhotoProvider('grupo-1')
                .overrideWith((ref) async => buildGroupCover()),
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

      await tester.tap(find.text('Remover capa'));
      await tester.pumpAndSettle();

      verifyNever(() => repository.requestDrain());
    });
  });
}

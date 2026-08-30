import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/pinned_message.dart';
import 'package:iasd_conecta/features/profile/data/profile_repository.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:iasd_conecta/features/profile/presentation/my_profile_page.dart';
import 'package:mocktail/mocktail.dart';

/// Change `alcance-do-titular-sobre-texto-proprio` — a seção de "Meu Perfil"
/// que lista as próprias mensagens fixadas e desfixa cada uma.
///
/// Julgada na largura de celular (360).

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockChatRepository extends Mock implements ChatRepository {}

const _profile = Profile(
  name: 'Ana Souza',
  gender: Gender.female,
  age: 30,
  lgpdConsentAccepted: true,
  nickname: 'Aninha',
);

PinnedMessage _pinned({String id = 'm1', String space = 'Grupo de Jovens'}) {
  return PinnedMessage(
    id: id,
    text: 'o ponto de encontro mudou',
    pinnedAt: DateTime.utc(2026, 8, 16, 12),
    spaceName: space,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PinnedMessage> pinned,
  MockChatRepository? chatRepo,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final profileRepo = MockProfileRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo),
        myProfileProvider.overrideWith((ref) async => _profile),
        churchesProvider.overrideWith((ref) async => const []),
        myPinnedMessagesProvider.overrideWith((ref) async => pinned),
        if (chatRepo != null) chatRepositoryProvider.overrideWithValue(chatRepo),
      ],
      child: const MaterialApp(home: MyProfilePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista vazia não desenha seção nenhuma', (tester) async {
    await _pump(tester, pinned: const []);

    expect(find.text('Mensagens fixadas'), findsNothing);
    expect(find.text('Desfixar'), findsNothing);
  });

  testWidgets('lista com fixadas mostra texto, espaço e botão de desfixar',
      (tester) async {
    await _pump(tester, pinned: [_pinned()]);

    expect(find.text('Mensagens fixadas'), findsOneWidget);
    expect(find.text('o ponto de encontro mudou'), findsOneWidget);
    expect(find.text('Grupo de Jovens'), findsOneWidget);
    expect(find.text('Desfixar'), findsOneWidget);
  });

  testWidgets('desfixar tira a linha na hora, sem recarregar', (tester) async {
    var fetchCount = 0;
    final chatRepo = MockChatRepository();
    when(() => chatRepo.unpinMyMessage('m1')).thenAnswer((_) async {});

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profileRepo = MockProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profileRepo),
          myProfileProvider.overrideWith((ref) async => _profile),
          churchesProvider.overrideWith((ref) async => const []),
          myPinnedMessagesProvider.overrideWith((ref) {
            fetchCount++;
            return Future.value([_pinned()]);
          }),
          chatRepositoryProvider.overrideWithValue(chatRepo),
        ],
        child: const MaterialApp(home: MyProfilePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(fetchCount, 1);

    await tester.ensureVisible(find.text('Desfixar'));
    await tester.tap(find.text('Desfixar'));
    await tester.pumpAndSettle();

    expect(find.text('o ponto de encontro mudou'), findsNothing);
    verify(() => chatRepo.unpinMyMessage('m1')).called(1);
    // SEM RECARREGAR: a busca não roda de novo.
    expect(fetchCount, 1);
  });

  testWidgets(
    'falha ao desfixar mantém a linha e diz o que aconteceu',
    (tester) async {
      final chatRepo = MockChatRepository();
      when(() => chatRepo.unpinMyMessage('m1'))
          .thenThrow(StateError('esta mensagem não pôde ser desfixada por você'));

      await _pump(tester, pinned: [_pinned()], chatRepo: chatRepo);

      await tester.ensureVisible(find.text('Desfixar'));
      await tester.tap(find.text('Desfixar'));
      await tester.pumpAndSettle();

      // NÃO some com o item sobre uma operação que não deu certo.
      expect(find.text('o ponto de encontro mudou'), findsOneWidget);
      expect(find.textContaining('Não deu pra desfixar'), findsOneWidget);
    },
  );
}

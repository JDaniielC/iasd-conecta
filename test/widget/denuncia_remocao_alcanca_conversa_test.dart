import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/domain/message_report.dart';
import 'package:iasd_conecta/features/chat/presentation/message_reports_page.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../chat_canal_helper.dart';

/// Change `chat-de-grupo-e-acao`, convergência 6 — remover pela tela de
/// DENÚNCIAS tem de alcançar a conversa que está montada atrás dela.
///
/// A tela de denúncias é aberta por `context.push` a partir da conversa, então
/// o `chatProvider` daquele espaço continua vivo enquanto ela está por cima.
/// Enquanto a remoção daqui só invalidava `messageReportsProvider`, quem
/// moderava voltava para a conversa e lia o texto que acabou de mandar tirar —
/// medido em 2026-08-16 com o canal caído: `texto_ainda_na_conversa=true`,
/// `lapide=false`.
///
/// É a mesma frase de decisão do design, atravessando de tela: "toda ação da
/// pessoa que muda esse conjunto atualiza a tela sem depender de o canal estar
/// de pé".

class MockChatRepository extends Mock implements ChatRepository {}

const _space = ChatSpace.group('g1');

final _report = MessageReport(
  id: 'r1',
  reason: 'ofendeu a Beltrana',
  state: MessageReportState.pending,
  createdAt: DateTime.utc(2026, 8, 14),
  messageId: 'm1',
  messageText: 'o que foi denunciado',
);

void main() {
  setUpAll(registerChatFallbacks);

  testWidgets('a conversa relê depois da remoção feita nas denúncias', (
    tester,
  ) async {
    final repository = MockChatRepository();
    var historyCalls = 0;
    when(
      () => repository.fetchHistory(
        groupId: any(named: 'groupId'),
        actionId: any(named: 'actionId'),
      ),
    ).thenAnswer((_) async {
      historyCalls++;
      return [
        Message(
          id: 'm1',
          authorId: 'outra',
          createdAt: DateTime.utc(2026, 8, 14, 10),
          groupId: 'g1',
          // Na segunda leitura o servidor já devolve a lápide.
          text: historyCalls == 1 ? 'o que foi denunciado' : null,
          removedAt: historyCalls == 1 ? null : DateTime.utc(2026, 8, 14, 11),
          authorName: 'Beltrana',
        ),
      ];
    });
    when(() => repository.removeMessage(any())).thenAnswer((_) async {});

    final fake = FakeRealtime();
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(fake.client),
        chatRepositoryProvider.overrideWithValue(repository),
        canModerateSpaceProvider(_space).overrideWith((ref) async => true),
        messageReportsProvider(_space).overrideWith((ref) async => [_report]),
        orphanMessageReportsProvider.overrideWith((ref) async => const []),
        isDistrictAdminProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(container.dispose);

    // A conversa está VIVA atrás — é o que `context.push` produz, e sem isto o
    // teste provaria só que `invalidate` não estoura.
    //
    // `container.listen` e não uma segunda tela: o que importa é o provider
    // continuar com ouvinte, que é a condição em que `invalidate` faz algo.
    final subscription = container.listen(chatProvider(_space), (_, _) {});
    addTearDown(subscription.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MessageReportsPage(space: _space)),
      ),
    );
    await tester.pumpAndSettle();

    expect(historyCalls, 1);
    expect(
      container.read(chatProvider(_space)).value!.messages.single.text,
      'o que foi denunciado',
    );

    await tester.tap(find.text('Remover mensagem'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    // `pump` e não `pumpAndSettle`: a invalidação põe um `CircularProgress`
    // em cena, e ele anima para sempre — `pumpAndSettle` nunca voltaria.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    verify(() => repository.removeMessage('m1')).called(1);
    expect(
      historyCalls,
      2,
      reason: 'a conversa atrás precisa reler — o canal pode estar caído',
    );
    final message = container.read(chatProvider(_space)).value!.messages.single;
    expect(message.text, isNull);
    expect(message.tombstone, MessageTombstone.removedByModeration);
  });
}

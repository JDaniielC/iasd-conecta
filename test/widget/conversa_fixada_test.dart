import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/chat_limits.dart';
import 'package:iasd_conecta/features/chat/domain/chat_state.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_page.dart';
import 'package:mocktail/mocktail.dart';

/// Change `mensagem-fixada`, seção 7 — a faixa de fixadas na LARGURA DE
/// CELULAR.
///
/// O caso que manda no desenho é o pior possível e é alcançável de verdade: o
/// teto de fixadas, cada uma no tamanho máximo de mensagem. Expandidas, três
/// mensagens de 2000 caracteres ocupam mais que uma tela de celular inteira, e
/// a conversa — que é o motivo de a pessoa ter aberto — ficaria abaixo do
/// primeiro rolar.
///
/// JULGAR NO CELULAR, NUNCA NO DESKTOP. Numa janela larga a faixa cabe com
/// folga e o teste não mediria nada.

class MockChatRepository extends Mock implements ChatRepository {}

const _space = ChatSpace.group('g1');

/// O tamanho máximo de uma mensagem, o mesmo do `check`
/// `mensagens_texto_no_limite`.
const _maxLength = 2000;

class _FixedChatNotifier extends ChatNotifier {
  _FixedChatNotifier(this.fixed, {this.pinRefusal}) : super(_space);

  final ChatState fixed;

  /// A recusa que o banco devolveria ao fixar. Nula quando a fixação passa.
  final SendRefusal? pinRefusal;

  @override
  Future<ChatState> build() async => fixed;

  @override
  Future<void> pin(String messageId) async {
    final refusal = pinRefusal;
    if (refusal != null) throw refusal;
  }
}

Message _message({
  required String id,
  String? text = 'combinado',
  String authorId = 'autor-1',
  DateTime? pinnedAt,
  DateTime? removedAt,
  int minute = 0,
}) => Message(
  id: id,
  authorId: authorId,
  createdAt: DateTime(2026, 8, 14, 19, minute),
  groupId: 'g1',
  text: text,
  removedAt: removedAt,
  pinnedAt: pinnedAt,
  pinnedBy: pinnedAt == null ? null : 'dono-1',
  authorName: 'Ana',
);

Future<void> _pumpChat(
  WidgetTester tester, {
  required ChatState chatState,
  bool canModerate = false,
  String uid = 'autor-1',
  SendRefusal? pinRefusal,
}) async {
  // 360x800: a largura em que a faixa compete com a conversa de verdade.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/grupos/g1/conversa',
    routes: [
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, state) =>
            const ChatPage(space: _space, title: 'SevenBikers'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(uid),
        chatRepositoryProvider.overrideWithValue(MockChatRepository()),
        chatProvider(_space).overrideWith(
          () => _FixedChatNotifier(chatState, pinRefusal: pinRefusal),
        ),
        canModerateSpaceProvider(
          _space,
        ).overrideWith((ref) async => canModerate),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('7.1 — o teto de fixadas, no tamanho máximo, num celular', () {
    /// Três fixadas de 2000 caracteres cada — o pior caso alcançável.
    ChatState worstCase() {
      final pinned = [
        for (var i = 0; i < ChatLimits.pinnedCeiling; i++)
          _message(
            id: 'f$i',
            // Uma primeira palavra distinta por fixada, para o teste poder
            // dizer QUAL está na tela, e um corpo que estoura a tela sozinho.
            text: 'Fixada$i ${'combinação longa ' * (_maxLength ~/ 18)}',
            pinnedAt: DateTime(2026, 8, 14, 20, i),
            minute: i,
          ),
      ];
      return ChatState(
        messages: [
          ...pinned,
          _message(id: 'm1', text: 'A conversa continua aqui', minute: 30),
        ],
        connection: ChatConnection.live,
        pinned: pinned.reversed.toList(),
      );
    }

    testWidgets('a conversa continua visível sem nenhuma interação', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: worstCase());

      // A FAIXA VEM RECOLHIDA, e é isso que deixa a conversa à vista. Se ela
      // viesse expandida, este `expect` falharia — e é exatamente o defeito que
      // o requisito descreve.
      expect(
        find.text('A conversa continua aqui'),
        findsOneWidget,
        reason: 'a conversa é o motivo de a pessoa ter aberto a tela',
      );
      expect(find.text('3 de 3 mensagens fixadas'), findsOneWidget);

      // Visível DE VERDADE, e não apenas presente na árvore: um widget
      // empurrado para fora da tela continua encontrável pelo `find`.
      final conversation = tester.getRect(
        find.text('A conversa continua aqui'),
      );
      expect(
        conversation.top,
        lessThan(800),
        reason: 'a faixa empurrou a conversa para fora da tela',
      );
    });

    testWidgets('a faixa se expande sob toque, e não vem expandida', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: worstCase());

      // Recolhida, cada fixada ocupa UMA linha.
      final collapsed = tester.getSize(find.byType(ChatPage));
      final bandBefore = tester.getRect(
        find.text('3 de 3 mensagens fixadas'),
      );

      await tester.tap(find.text('3 de 3 mensagens fixadas'));
      await tester.pumpAndSettle();

      // Expandida, o texto inteiro aparece — e a faixa NÃO cresce sem limite:
      // ela tem teto de altura e rola por dentro. Sem isso, expandir devolveria
      // o problema que recolher resolveu, e depois de um toque, que é pior.
      final band = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(
        band.height,
        lessThanOrEqualTo(collapsed.height * 0.36),
        reason: 'a faixa expandida engoliu a tela',
      );
      expect(bandBefore.top, greaterThanOrEqualTo(0));
    });

    testWidgets('a conversa continua ROLÁVEL com a faixa na tela', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: worstCase());

      final list = find.byType(ListView);
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, 200));
      await tester.pumpAndSettle();
      // Rolar não pode ter derrubado a tela nem a faixa.
      expect(tester.takeException(), isNull);
      expect(find.text('3 de 3 mensagens fixadas'), findsOneWidget);
    });
  });

  testWidgets('o teto só aparece na faixa quando ele está cheio', (
    tester,
  ) async {
    // Dizer "1 de 3" o tempo todo transformaria um limite raro em ruído
    // permanente. O contraste é o caso do teto cheio, acima.
    final pinned = _message(id: 'f0', pinnedAt: DateTime(2026, 8, 14, 20));
    await _pumpChat(
      tester,
      chatState: ChatState(
        messages: [pinned],
        connection: ChatConnection.live,
        pinned: [pinned],
      ),
    );

    expect(find.text('1 mensagem fixada'), findsOneWidget);
    expect(find.textContaining('de 3'), findsNothing);
  });

  testWidgets('7.2 — chat sem fixada não mostra faixa nenhuma', (tester) async {
    await _pumpChat(
      tester,
      chatState: ChatState(
        messages: [_message(id: 'm1', text: 'Saímos 6h da praça')],
        connection: ChatConnection.live,
      ),
    );

    expect(find.text('Saímos 6h da praça'), findsOneWidget);
    expect(
      find.byIcon(Icons.push_pin_outlined),
      findsNothing,
      reason: 'faixa vazia dizendo que não há nada fixado é espaço gasto à toa',
    );
    expect(find.textContaining('fixada'), findsNothing);
  });

  group('7.3 — a ação aparece só para quem pode executá-la', () {
    testWidgets('participante comum não vê Fixar', (tester) async {
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [_message(id: 'm1')],
          connection: ChatConnection.live,
        ),
      );

      // FIXAR é só da autoridade do espaço, e nem o autor entra: fixar decide
      // o que todo mundo vê primeiro, e tira a mensagem do prazo de 30 dias.
      expect(find.text('Fixar'), findsNothing);
      // O contraste: Remover ele vê, porque a mensagem é dele. Sem esta linha
      // o caso passaria também se a barra de ações inteira sumisse.
      expect(find.text('Remover'), findsOneWidget);
    });

    testWidgets('quem manda no espaço vê Fixar', (tester) async {
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [_message(id: 'm1')],
          connection: ChatConnection.live,
        ),
        canModerate: true,
      );

      expect(find.text('Fixar'), findsOneWidget);
      expect(find.text('Desfixar'), findsNothing);
    });

    testWidgets('o autor vê Desfixar na própria mensagem fixada', (
      tester,
    ) async {
      final pinned = _message(id: 'm1', pinnedAt: DateTime(2026, 8, 14, 20));
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [pinned],
          connection: ChatConnection.live,
          pinned: [pinned],
        ),
      );

      // Ele NÃO tem autoridade no espaço, e mesmo assim desfixa: é o que
      // devolve a ele o controle do prazo do que escreveu. Fixar de volta
      // continua fora do alcance dele.
      expect(find.text('Desfixar'), findsOneWidget);
      expect(find.text('Fixar'), findsNothing);
    });

    testWidgets('quem não é autor nem autoridade não desfixa', (tester) async {
      final pinned = _message(
        id: 'm1',
        authorId: 'outra-pessoa',
        pinnedAt: DateTime(2026, 8, 14, 20),
      );
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [pinned],
          connection: ChatConnection.live,
          pinned: [pinned],
        ),
      );

      expect(find.text('Desfixar'), findsNothing);
      expect(
        find.byTooltip('Desfixar'),
        findsNothing,
        reason: 'nem o botão da faixa',
      );
    });
  });

  group('o teto atingido DIZ o que fazer, na tela', () {
    // Convergência 2. A recusa estava provada no banco e na API; a FRASE, em
    // lugar nenhum — nenhum teste tocava "Fixar". É a recusa muda que esta
    // feature existe para não ter, e ela passaria despercebida se alguém
    // trocasse o texto.
    ChatState withCeilingFull() {
      final pinned = [
        for (var i = 0; i < ChatLimits.pinnedCeiling; i++)
          _message(
            id: 'f$i',
            text: 'fixada $i',
            pinnedAt: DateTime(2026, 8, 14, 20, i),
            minute: i,
          ),
      ];
      return ChatState(
        messages: [...pinned, _message(id: 'nova', text: 'a que não cabe')],
        connection: ChatConnection.live,
        pinned: pinned.reversed.toList(),
      );
    }

    testWidgets('a frase manda desfixar e nomeia o teto', (tester) async {
      await _pumpChat(
        tester,
        chatState: withCeilingFull(),
        canModerate: true,
        pinRefusal: const SendRefusal(
          kind: SendRefusalKind.pinnedCeiling,
          ceiling: ChatLimits.pinnedCeiling,
        ),
      );

      // A ação continua oferecida com o teto cheio, de propósito: escondê-la
      // seria a recusa muda. Quem explica é a frase.
      await tester.tap(find.text('Fixar').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Desfixe'), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
    });

    testWidgets('recusa que não é o teto não vira a frase do teto', (
      tester,
    ) async {
      // O contraste. Sem ele, o caso de cima passaria também se a tela
      // mostrasse sempre a mesma frase para qualquer falha ao fixar.
      await _pumpChat(
        tester,
        chatState: withCeilingFull(),
        canModerate: true,
        pinRefusal: null,
      );

      await tester.tap(find.text('Fixar').last);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('7.4 — lápide nunca aparece na faixa', (tester) async {
    // O banco desfixa sozinho quem perde o texto — é o gatilho, não a tela.
    // Este caso monta o estado que o banco NÃO produz, e prova que a tela
    // também não o desenha: uma marca de "mensagem removida" no alto do chat
    // ocuparia vaga do teto sem informar nada.
    final tombstone = _message(
      id: 'm1',
      text: null,
      removedAt: DateTime(2026, 8, 14, 19, 5),
    );
    final alive = _message(
      id: 'm2',
      text: 'esta continua fixada',
      pinnedAt: DateTime(2026, 8, 14, 20),
      minute: 6,
    );

    await _pumpChat(
      tester,
      chatState: ChatState(
        messages: [tombstone, alive],
        connection: ChatConnection.live,
        pinned: [alive],
      ),
    );

    // Duas vezes, e é o certo: a fixada vive na faixa E na conversa. Fixar
    // muda a posição, não tira a mensagem de onde ela foi dita.
    expect(find.text('esta continua fixada'), findsNWidgets(2));
    expect(find.text('1 mensagem fixada'), findsOneWidget);
    // A lápide aparece na CONVERSA — é o registro de que algo esteve ali —,
    // e uma vez só: se ela tivesse entrado na faixa, seriam duas.
    expect(find.text('Mensagem removida.'), findsOneWidget);
  });
}

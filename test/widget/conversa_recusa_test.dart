import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/chat_state.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/domain/send_refusal.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_page.dart';
import 'package:mocktail/mocktail.dart';

class MockChatRepository extends Mock implements ChatRepository {}

/// Change `filtro-e-intervalo-de-mensagem`, tarefas 6.1 a 6.4 — o que a pessoa
/// LÊ quando o banco recusa.
///
/// O banco já provou as três recusas (`test/integration/filtro_palavra_*`,
/// `ritmo_de_mensagem_test.dart`, `limites_de_chat_test.dart`). O que falta
/// provar é que a tela as distingue: as três chegam como exceção, e uma tela que
/// dissesse "não deu pra enviar" para todas passaria em qualquer teste de banco
/// e deixaria a pessoa tentando de novo sem saber o que mudar.
///
/// **Cada caso vem com o seu contraste.** Verificar só que a frase de palavra
/// aparece não prova nada — ela apareceria também numa tela de frase única.
///
/// TUDO NA LARGURA DE CELULAR (6.4). A contagem regressiva e o nome da palavra
/// disputam espaço com o campo de envio numa tela estreita, e é aí que se julga.

const _space = ChatSpace.group('g1');

/// Um notifier cujo `send` recusa do jeito escolhido.
///
/// Recusa CONFIGURÁVEL e não um mock por caso: as três recusas são o mesmo
/// caminho com um `kind` diferente, e é justamente a diferença de desenho entre
/// elas que estes casos medem.
class _RefusingChatNotifier extends ChatNotifier {
  _RefusingChatNotifier(this.refusal, this.messages) : super(_space);

  /// Nulo faz o envio dar certo — é o caso de contraste de 6.3.
  SendRefusal? refusal;

  final List<Message> messages;

  var sendCount = 0;

  @override
  Future<ChatState> build() async =>
      ChatState(messages: messages, connection: ChatConnection.live);

  @override
  Future<void> send(String text) async {
    sendCount++;
    final current = refusal;
    if (current != null) throw current;
  }
}

Future<_RefusingChatNotifier> _pumpChat(
  WidgetTester tester, {
  SendRefusal? refusal,
  ChatRepository? repository,
  List<Message> messages = const [],
}) async {
  // 360 de largura: onde a faixa de recusa, o campo e o botão competem de
  // verdade. No desktop qualquer frase cabe, e o caso não mediria nada.
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final notifier = _RefusingChatNotifier(refusal, messages);
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
        currentUserIdProvider.overrideWithValue('autor-1'),
        chatRepositoryProvider.overrideWithValue(
          repository ?? MockChatRepository(),
        ),
        chatProvider(_space).overrideWith(() => notifier),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

/// Digita e aperta enviar.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Enviar'));
  await tester.pump();
}

void main() {
  group('6.1 — as três recusas dizem coisas diferentes', () {
    testWidgets('palavra bloqueada mostra QUAL palavra', (tester) async {
      await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.blockedWord,
          blockedWord: 'xatoxo',
        ),
      );

      await _type(tester, 'seu xatoxo');

      expect(
        find.textContaining('xatoxo'),
        findsWidgets,
        reason:
            'sem a palavra a recusa não é corrigível: a pessoa reescreve no '
            'escuro até desistir',
      );
      // E não vira uma espera: palavra bloqueada se resolve editando o texto.
      expect(find.textContaining('Espere'), findsNothing);
    });

    testWidgets('intervalo mostra o tempo que falta', (tester) async {
      await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      );

      await _type(tester, 'e mais uma');

      expect(find.textContaining('3 segundos'), findsOneWidget);
      expect(find.textContaining('Espere'), findsOneWidget);
    });

    testWidgets('teto diz coisa DISTINTA do intervalo', (tester) async {
      // O contraste é o teste. As duas recusas são de ritmo, e uma tela que
      // dissesse "espere 3 segundos" para as duas faria a pessoa esperar,
      // tentar, e ser recusada de novo sem entender.
      await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.windowCeiling,
          retryAfter: Duration(minutes: 2),
        ),
      );

      await _type(tester, 'a vigésima primeira');

      expect(find.textContaining('muitas mensagens seguidas'), findsOneWidget);
      expect(find.textContaining('2 minutos'), findsOneWidget);
      expect(
        find.textContaining('Espere'),
        findsNothing,
        reason: 'a frase do teto não pode ser a do intervalo',
      );
    });

    testWidgets('a faixa de palavra some quando a pessoa edita o texto', (
      tester,
    ) async {
      // CONVERGENCE 1. A recusa por palavra não tem `retryAfter`, então não há
      // relógio para apagá-la — ela ficava na tela até um envio dar certo,
      // dizendo "troque essa parte" depois de a pessoa ter trocado.
      final notifier = await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.blockedWord,
          blockedWord: 'xatoxo',
        ),
      );

      await _type(tester, 'seu xatoxo');
      expect(find.textContaining('xatoxo'), findsWidgets);

      // A pessoa corrige. Ninguém apertou nada.
      notifier.refusal = null;
      await tester.enterText(find.byType(TextField), 'combinado às 19h');
      await tester.pump();

      expect(
        find.textContaining('não é aceita'),
        findsNothing,
        reason: 'a faixa não pode sobreviver à correção que ela mesma pediu',
      );
    });

    testWidgets('a faixa de RITMO não some quando a pessoa digita', (
      tester,
    ) async {
      // O contraste, e ele é o que impede a correção acima de virar exagero.
      // Apagar a recusa de ritmo ao digitar seria mentir ao contrário: o envio
      // continua fechado, e a explicação de por quê tem de continuar à vista.
      await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      );

      await _type(tester, 'e mais uma');
      expect(find.textContaining('Espere'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'outra coisa qualquer');
      await tester.pump();

      expect(find.textContaining('Espere'), findsOneWidget);
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(button.onPressed, isNull, reason: 'e o envio segue fechado');

      // Deixa o relógio terminar para não vazar `Timer`.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('recusa de ritmo SEM tempo expira sozinha, com envio aberto', (
      tester,
    ) async {
      // CONVERGENCE 2. `retryAfter` nulo é o caso que `SendRefusal._seconds`
      // trata de propósito — `hint` que não chega ou não é número. Sem relógio
      // para descontar, a faixa ficava na tela PARA SEMPRE: `_onTextChanged` só
      // apaga a de palavra, e nenhum outro caminho a alcançava.
      final notifier = await _pumpChat(
        tester,
        refusal: const SendRefusal(kind: SendRefusalKind.tooSoon),
      );

      await _type(tester, 'e mais uma');
      expect(find.textContaining('Espere um instante'), findsOneWidget);

      // O ENVIO CONTINUA ABERTO, e é decisão: a tela não sabe até quando
      // esperar, e fechar o botão por tempo indeterminado seria pior do que
      // deixar a pessoa tentar e o servidor decidir.
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'sem saber o tempo, quem decide é o servidor',
      );

      // Ninguém toca na tela; só a explicação expira.
      notifier.refusal = null;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Espere'),
        findsNothing,
        reason: 'faixa que nada apaga é faixa que fica para sempre',
      );
    });

    testWidgets('sem recusa, nenhuma faixa aparece', (tester) async {
      // O contraste que fecha o grupo: sem ele, uma tela que mostrasse a faixa
      // o tempo todo passaria nos três casos acima.
      await _pumpChat(tester);
      await _type(tester, 'quem leva o som?');

      expect(find.textContaining('Espere'), findsNothing);
      expect(find.textContaining('não é aceita'), findsNothing);
      expect(find.textContaining('muitas mensagens'), findsNothing);
    });
  });

  group('6.2 — o texto digitado não se perde em recusa nenhuma', () {
    for (final (name, refusal) in <(String, SendRefusal)>[
      (
        'palavra',
        SendRefusal(
          kind: SendRefusalKind.blockedWord,
          blockedWord: 'xatoxo',
        ),
      ),
      (
        'intervalo',
        SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      ),
      (
        'teto',
        SendRefusal(
          kind: SendRefusalKind.windowCeiling,
          retryAfter: Duration(minutes: 2),
        ),
      ),
    ]) {
      testWidgets('recusa por $name mantém o texto no campo', (tester) async {
        await _pumpChat(tester, refusal: refusal);
        await _type(tester, 'combinado às 19h no ponto de sempre');

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(
          field.controller!.text,
          'combinado às 19h no ponto de sempre',
          reason:
              'perder a frase por causa de uma recusa que se corrige esperando '
              'ou editando transforma um limite em punição',
        );
      });
    }

    testWidgets('no SUCESSO o campo limpa', (tester) async {
      // O contraste: sem ele, um `_send` que nunca limpasse passaria nos três
      // casos acima.
      await _pumpChat(tester);
      await _type(tester, 'quem leva o som?');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });
  });

  group('6.3 — o envio volta a abrir sozinho', () {
    testWidgets('fechado durante a espera, aberto depois dela', (tester) async {
      final notifier = await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      );

      await _type(tester, 'e mais uma');
      expect(notifier.sendCount, 1);

      // Fechado: o botão perdeu o `onPressed`, e apertá-lo não chega ao
      // servidor. Sem isto a pessoa tentaria de novo e levaria a mesma recusa.
      var button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
      expect(button.onPressed, isNull);
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump();
      expect(notifier.sendCount, 1, reason: 'o toque não passou');

      // O tempo passa e NINGUÉM toca na tela. O relógio é quem reabre.
      notifier.refusal = null;
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Espere'),
        findsNothing,
        reason: 'a faixa some com a espera',
      );
      button = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump();
      expect(notifier.sendCount, 2, reason: 'e agora o envio chega');
    });

    testWidgets('a contagem regressiva anda', (tester) async {
      await _pumpChat(
        tester,
        refusal: const SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      );
      await _type(tester, 'e mais uma');
      expect(find.textContaining('3 segundos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(
        find.textContaining('2 segundos'),
        findsOneWidget,
        reason: 'contador parado é indistinguível de tela travada',
      );

      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('1 segundo'), findsOneWidget);

      // Deixa o relógio terminar para não vazar `Timer` no fim do caso.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });

  group('6.4 — as três recusas cabem na largura de celular', () {
    for (final (name, refusal) in <(String, SendRefusal)>[
      (
        'palavra longa',
        SendRefusal(
          kind: SendRefusalKind.blockedWord,
          blockedWord: 'palavradeconversamuitocompridamesmo',
        ),
      ),
      (
        'intervalo',
        SendRefusal(
          kind: SendRefusalKind.tooSoon,
          retryAfter: Duration(seconds: 3),
        ),
      ),
      (
        'teto',
        SendRefusal(
          kind: SendRefusalKind.windowCeiling,
          retryAfter: Duration(minutes: 2),
        ),
      ),
    ]) {
      testWidgets('$name não estoura os 360 de largura', (tester) async {
        await _pumpChat(tester, refusal: refusal);
        await _type(tester, 'texto que fica no campo enquanto a faixa aparece');

        // `tester.takeException` pega o `RenderFlex overflowed` que o Flutter
        // levanta em teste — que é exatamente o defeito que 6.4 procura, e o
        // único que não aparece no desktop.
        expect(tester.takeException(), isNull);

        // E a faixa não empurrou o campo para fora da tela: ele continua
        // desenhado e digitável.
        expect(find.byType(TextField), findsOneWidget);
      });
    }
  });

  group('6.2 — a denúncia recusada também não perde o texto', () {
    /// O caminho da denúncia é OUTRO: ele não passa pelo `ChatNotifier`, vai
    /// direto ao repositório, e o texto mora num diálogo que fecha.
    ///
    /// Foi por isso que ele quebrou. A primeira versão desta change fechava o
    /// diálogo antes de escrever, e a recusa chegava por `SnackBar` com o
    /// `controller` já descartado — quem denunciava uma ofensa CITANDO a
    /// ofensa era recusado e tinha de reescrever do zero. Achado pelo agente
    /// `advogado-digital`, e o efeito era desestimular justamente o mecanismo
    /// em que a moderação deste app se apoia.
    testWidgets('recusa por palavra reabre o diálogo com o texto', (
      tester,
    ) async {
      final repository = MockChatRepository();
      var attempts = 0;
      when(() => repository.reportMessage(any(), any())).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) {
          throw const SendRefusal(
            kind: SendRefusalKind.blockedWord,
            blockedWord: 'xatoxo',
          );
        }
      });

      await _pumpChat(
        tester,
        repository: repository,
        messages: [
          Message(
            id: 'm1',
            // De OUTRA pessoa: "Denunciar" só aparece em mensagem alheia.
            authorId: 'outra-1',
            createdAt: DateTime(2026, 8, 16, 19),
            groupId: 'g1',
            text: 'mensagem alheia',
            authorName: 'Ana',
          ),
        ],
      );

      await tester.longPress(find.text('mensagem alheia'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Denunciar'));
      await tester.pumpAndSettle();

      const reason = 'ela me chamou de xatoxo na frente de todo mundo';
      await tester.enterText(find.byType(TextField).last, reason);
      await tester.tap(find.widgetWithText(FilledButton, 'Denunciar'));
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(
        find.textContaining('xatoxo'),
        findsWidgets,
        reason: 'a recusa diz qual palavra, DENTRO do diálogo',
      );

      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(
        field.controller!.text,
        reason,
        reason:
            'quem denuncia uma ofensa cita a ofensa; perder o texto é mandar a '
            'pessoa reescrever do zero sem poder citar o que denuncia',
      );

      // E ainda dá para corrigir e insistir, sem sair da tela.
      await tester.enterText(
        find.byType(TextField).last,
        'ela me ofendeu na frente de todo mundo',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Denunciar'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Denúncia enviada. Quem cuida do espaço vai ver.'),
          findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/chat/data/chat_repository.dart';
import 'package:iasd_conecta/features/chat/domain/chat_state.dart';
import 'package:iasd_conecta/features/chat/domain/message.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_gate_page.dart';
import 'package:iasd_conecta/features/chat/presentation/chat_page.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:mocktail/mocktail.dart';

class MockChatRepository extends Mock implements ChatRepository {}

/// `ChatNotifier` com um estado fixo, para os casos que provam DESENHO.
///
/// A composição da lista — quem vence entre servidor e sobreposição local — é
/// provada em `conversa_sem_canal_test.dart`, com o notifier de verdade e o
/// canal morto. Aqui o que se prova é o que a pessoa lê na tela para cada
/// estado, e um estado fixo é o recorte certo: ele deixa montar combinações que
/// o notifier real levaria meia dúzia de eventos para produzir.
class _FixedChatNotifier extends ChatNotifier {
  _FixedChatNotifier(this.fixed) : super(_space);

  final ChatState fixed;

  @override
  Future<ChatState> build() async => fixed;
}

/// Change `chat-de-grupo-e-acao`, tarefas 9.3 a 9.6 — a prova no cliente.
///
/// O banco já provou quem lê e quem escreve (`test/integration/chat_*`). O que
/// falta provar é o que a PESSOA vê quando a resposta é "não": um "não" mudo é
/// indistinguível de app quebrado, e nenhum teste de policy pega isso.
///
/// Por isso cada caso aqui vem com o seu contraste. Verificar só que a
/// explicação de idade aparece não prova nada — ela apareceria também se a tela
/// mostrasse sempre a mesma frase para qualquer recusa, que é justamente o
/// defeito que `ChatGatePage` existe para não ter.
const _space = ChatSpace.group('g1');

final _group = Group(
  id: 'g1',
  name: 'SevenBikers',
  category: 'Ministério Jovem',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

/// `authorId` igual ao `currentUserIdProvider` dos testes: é o caso em que a
/// mensagem tem ações (Remover), que é a árvore mais cheia — a que tem mais
/// chance de esconder um `null` renderizado.
Message _message({
  required String id,
  String? text,
  DateTime? removedAt,
  String? authorName = 'Ana',
  int minute = 0,
}) {
  return Message(
    id: id,
    authorId: 'autor-1',
    createdAt: DateTime(2026, 8, 14, 19, minute),
    groupId: 'g1',
    text: text,
    removedAt: removedAt,
    authorName: authorName,
  );
}

/// Monta a `ChatPage` já resolvida, sem passar pelo portão.
///
/// O repositório é falso mesmo quando o teste não o usa: sem ele,
/// `chatRepositoryProvider` cairia em `supabaseClientProvider`, e um teste de
/// widget que toca a rede é um teste que quebra por motivo errado.
Future<void> _pumpChat(
  WidgetTester tester, {
  required ChatState chatState,
  bool readOnly = false,
}) async {
  final router = GoRouter(
    initialLocation: '/grupos/g1/conversa',
    routes: [
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, routerState) =>
            ChatPage(space: _space, title: 'SevenBikers', readOnly: readOnly),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('autor-1'),
        chatRepositoryProvider.overrideWithValue(MockChatRepository()),
        chatProvider(_space).overrideWith(() => _FixedChatNotifier(chatState)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Monta o portão com as duas respostas do banco separadas, que é o desenho de
/// `ChatGatePage`: `pode_ver_chat_*` diz "não" do mesmo jeito por idade e por
/// não pertencer ao espaço, e é `maior_de_idade()` que desempata.
Future<void> _pumpGate(
  WidgetTester tester, {
  required bool canSee,
  required bool isOfAge,
}) async {
  final router = GoRouter(
    initialLocation: '/grupos/g1/conversa',
    routes: [
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, routerState) => const ChatGatePage(space: _space),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('autor-1'),
        chatRepositoryProvider.overrideWithValue(MockChatRepository()),
        canSeeChatProvider(_space).overrideWith((ref) async => canSee),
        isOfAgeProvider.overrideWith((ref) async => isOfAge),
        groupProvider('g1').overrideWith((ref) async => _group),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('9.3 — o portão diz POR QUE não', () {
    testWidgets('menor de 18 vê a explicação de idade, não uma tela vazia', (
      tester,
    ) async {
      await _pumpGate(tester, canSee: false, isOfAge: false);

      expect(
        find.textContaining('18 anos ou mais'),
        findsOneWidget,
        reason:
            'Sem esta frase, quem é menor de idade só vê a conversa sumir — e '
            'a conclusão natural é que o app quebrou ou que alguém a excluiu.',
      );
      // A explicação precisa dizer que é regra do app, não decisão de alguém
      // sobre aquela pessoa: é a diferença entre uma regra e uma exclusão.
      expect(find.textContaining('regra do app'), findsOneWidget);
    });

    testWidgets('maior de 18 fora da atividade vê a outra explicação', (
      tester,
    ) async {
      // O contraste é o teste. `pode_ver_chat_grupo` devolve `false` nos dois
      // casos, então uma tela que mostrasse sempre a mesma frase passaria no
      // teste anterior e mentiria aqui — dizendo a um adulto que ele é menor
      // de idade.
      await _pumpGate(tester, canSee: false, isOfAge: true);

      expect(
        find.textContaining('de quem está nesta atividade'),
        findsOneWidget,
      );
      expect(
        find.textContaining('18 anos ou mais'),
        findsNothing,
        reason:
            'Explicação de idade para quem é maior de idade é informação '
            'falsa, e sobre um assunto em que a pessoa não tem como conferir.',
      );
    });
  });

  group('9.4 — sem tempo real o chat funciona E sinaliza', () {
    testWidgets('reconectando: as mensagens aparecem e a faixa avisa', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [_message(id: 'm1', text: 'Saímos 6h da praça')],
          connection: ChatConnection.reconnecting,
        ),
      );

      expect(find.text('Saímos 6h da praça'), findsOneWidget);
      expect(find.textContaining('Reconectando'), findsOneWidget);
      // O modo de falhar que este teste caça não é a faixa faltar — é a tela
      // tratar canal caído como "ainda carregando" e girar para sempre sobre
      // um histórico que já está na mão.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'Canal caído não é carregamento: o histórico já chegou.',
      );
    });

    testWidgets('sem tempo real: as mensagens aparecem e a faixa avisa', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [_message(id: 'm1', text: 'Saímos 6h da praça')],
          connection: ChatConnection.offline,
        ),
      );

      expect(find.text('Saímos 6h da praça'), findsOneWidget);
      expect(find.textContaining('Sem tempo real'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('ao vivo: nenhuma faixa', (tester) async {
      // Faixa permanente é ruído que ninguém lê — e aí, quando ela mudar para
      // "reconectando", ninguém lê também. Sem este caso, os dois anteriores
      // passariam com uma faixa fixa na tela.
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [_message(id: 'm1', text: 'Saímos 6h da praça')],
          connection: ChatConnection.live,
        ),
      );

      expect(find.text('Saímos 6h da praça'), findsOneWidget);
      expect(find.textContaining('Reconectando'), findsNothing);
      expect(find.textContaining('Sem tempo real'), findsNothing);
    });
  });

  group('9.5 — Grupo arquivado é histórico legível', () {
    final chatState = ChatState(
      messages: [_message(id: 'm1', text: 'Foi bom enquanto durou')],
      connection: ChatConnection.live,
    );

    testWidgets('arquivado mostra as mensagens sem campo de envio', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: chatState, readOnly: true);

      // Grupo arquivado não é caso de erro nem de tela vazia: o histórico é
      // justamente o que sobra dele.
      expect(find.text('Foi bom enquanto durou'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason:
            'O `insert` é recusado pela policy. Oferecer o campo faria a '
            'pessoa escrever para só então ouvir "não" como erro de servidor.',
      );
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('ativo mostra as mensagens COM campo de envio', (tester) async {
      // Sem este contraste, um `Composer` que nunca renderiza passaria no caso
      // acima — e o chat inteiro estaria mudo sem ninguém notar.
      await _pumpChat(tester, chatState: chatState, readOnly: false);

      expect(find.text('Foi bom enquanto durou'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });
  });

  group('9.7 — o limite de 2000 se diz ANTES do envio', () {
    // A cláusula "a operação é recusada, e a tela diz o limite antes do envio"
    // tem duas metades, e só a do banco tinha prova
    // (`test/integration/chat_escrita_test.dart`, '2000 caracteres passa, 2001
    // não'). A metade de tela não tinha asserção nenhuma — achado da
    // convergência 5.
    //
    // O que se perde sem ela: `_maxLength` e o gatilho do contador são números
    // escritos à mão em `chat_page.dart`, longe do `check`
    // `mensagens_texto_no_limite` que eles espelham. Uma regressão em qualquer
    // dos dois transforma a recusa educada num erro de servidor depois de a
    // pessoa ter digitado o texto inteiro.
    final chatState = ChatState(
      messages: [_message(id: 'm1', text: 'oi')],
      connection: ChatConnection.live,
    );

    bool sendEnabled(WidgetTester tester) =>
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed !=
        null;

    testWidgets('conversa curta não mostra contador — seria ruído', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: chatState);
      await tester.enterText(find.byType(TextField), 'às 19h');
      await tester.pump();

      expect(find.textContaining('/2000'), findsNothing);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('perto do limite o contador aparece, e o envio segue aberto', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: chatState);
      await tester.enterText(find.byType(TextField), 'a' * 1900);
      await tester.pump();

      expect(find.text('1900/2000'), findsOneWidget);
      expect(
        sendEnabled(tester),
        isTrue,
        reason: 'avisar não é impedir — 1900 caracteres o banco aceita',
      );
    });

    testWidgets('acima do limite o botão fecha, e o contador diz o número', (
      tester,
    ) async {
      await _pumpChat(tester, chatState: chatState);
      await tester.enterText(find.byType(TextField), 'a' * 2001);
      await tester.pump();

      expect(find.text('2001/2000'), findsOneWidget);
      expect(
        sendEnabled(tester),
        isFalse,
        reason:
            'o `check` do banco recusaria; a pessoa precisa saber disso antes '
            'de apertar, não como erro de servidor',
      );
    });
  });

  testWidgets(
    '9.6 — as três lápides têm textos distintos e nenhuma mostra null',
    (tester) async {
      // `Message.text` é nulo nas duas lápides, e o corpo da mensagem só sabe
      // disso olhando `tombstone`. Um `Text('${message.text}')` distraído
      // renderiza a string "null" e passa em qualquer teste que só procure a
      // frase certa — por isso a asserção final varre a árvore inteira.
      await _pumpChat(
        tester,
        chatState: ChatState(
          messages: [
            _message(id: 'm1', text: 'Alguém leva a bomba de ar?', minute: 1),
            _message(id: 'm2', removedAt: DateTime(2026, 8, 14, 20), minute: 2),
            // Autor de conta excluída também perde o nome: `authorName` nulo é o
            // caso real, e é outra porta por onde "null" chegaria à tela.
            _message(id: 'm3', authorName: null, minute: 3),
          ],
          connection: ChatConnection.live,
        ),
      );

      expect(find.text('Alguém leva a bomba de ar?'), findsOneWidget);
      // Duas frases DIFERENTES de propósito: "alguém tirou isso daqui" e "a
      // pessoa foi embora e levou o que era dela" são fatos distintos, e quem lê
      // merece saber qual foi.
      expect(find.text('Mensagem removida.'), findsOneWidget);
      expect(find.text('Mensagem de conta excluída.'), findsOneWidget);
      expect(find.text('Alguém'), findsOneWidget);

      expect(
        find.textContaining('null'),
        findsNothing,
        reason:
            'A palavra "null" na tela entrega que a lápide foi renderizada por '
            'interpolação em vez de por `tombstone`.',
      );
    },
  );
}

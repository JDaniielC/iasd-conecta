import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/change_log/change_log_providers.dart';
import 'package:iasd_conecta/features/change_log/domain/change_log_entry.dart';
import 'package:iasd_conecta/features/chat/chat_providers.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/group_detail_page.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

/// Change `chat-de-grupo-e-acao` — a metade do cenário "Menor de idade abre um
/// Grupo em que participa" que mora FORA da conversa.
///
/// `conversa_page_test.dart` prova o que a pessoa lê quando entra no chat.
/// Aqui a spec pede o contrário: que ela nunca chegue a entrar — "não existe
/// aba de conversa na tela" — e que o resto da tela siga inteiro, inclusive a
/// seção de mudanças. É a diferença entre esconder o chat e mutilar o Grupo.
///
/// Os dois casos existem em par de propósito. Só o caso "menor não vê" passaria
/// verde com o botão apagado para todo mundo, que é exatamente a regressão mais
/// provável em `canSeeChatProvider`.
class MockGroupRepository extends Mock implements GroupRepository {}

const _space = ChatSpace.group('g1');

final _group = Group(
  id: 'g1',
  name: 'SevenBikers',
  category: 'Ministério Jovem',
  schedule: 'sábados 6h',
  location: 'Praça Central',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

final _changeLog = [
  ChangeLogEntry(
    id: 'mudanca-1',
    type: ChangeLogType.memberJoined,
    createdAt: DateTime(2026, 8, 13, 10),
    groupId: 'g1',
    authorId: 'membro-1',
    authorName: 'Bia',
  ),
];

/// Abre o detalhe do Grupo com a resposta de `canSeeChatProvider` fixada.
///
/// O participante é o próprio Usuário da sessão: o cenário da spec é de quem
/// PARTICIPA do Grupo — se ele não participasse, a ausência do botão não
/// provaria nada sobre o corte de idade.
Future<void> _pumpGroupDetail(
  WidgetTester tester, {
  required bool canSeeChat,
}) async {
  // Celular: é onde a barra de ícones do título fica apertada, e onde um
  // ícone a mais ou a menos muda o que cabe.
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final groupRepo = MockGroupRepository();
  when(() => groupRepo.fetchGroup('g1')).thenAnswer((_) async => _group);
  when(() => groupRepo.fetchMembers('g1')).thenAnswer(
    (_) async => const [
      PublicProfile(id: 'dono-1', displayName: 'Dono'),
      PublicProfile(id: 'menor-1', displayName: 'Bia'),
    ],
  );

  final router = GoRouter(
    initialLocation: '/grupos/g1',
    routes: [
      GoRoute(
        path: '/grupos/:id',
        builder: (context, state) =>
            GroupDetailPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, state) => const Text('TELA_CONVERSA'),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        currentUserIdProvider.overrideWithValue('menor-1'),
        groupRepositoryProvider.overrideWithValue(groupRepo),
        canSeeChatProvider(_space).overrideWith((ref) async => canSeeChat),
        groupChangeLogProvider('g1').overrideWith((ref) async => _changeLog),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'menor de idade não encontra entrada de conversa, e o resto da tela fica inteiro',
    (tester) async {
      await _pumpGroupDetail(tester, canSeeChat: false);

      expect(
        find.byTooltip('Conversa'),
        findsNothing,
        reason:
            'o corte de 18 anos tira a entrada da tela, não só o acesso ao '
            'chat — botão que só recusa depois de tocado é promessa quebrada',
      );

      // O resto da tela funciona IGUAL: o Grupo, quem participa, e as outras
      // entradas que nada têm a ver com o chat.
      expect(find.text('SevenBikers'), findsOneWidget);
      expect(find.text('Ministério Jovem'), findsOneWidget);
      expect(find.text('Participantes'), findsOneWidget);
      expect(find.text('Bia'), findsOneWidget);
      expect(find.byTooltip('Rodadas de Votação'), findsOneWidget);
      expect(find.byTooltip('Líder/Diretor de Ministério'), findsOneWidget);
      expect(find.text('Sair do Grupo/Ministério'), findsOneWidget);

      // A seção de mudanças, que a spec cita por nome: ela vive no rodapé da
      // mesma lista dos participantes, e some junto se a lista quebrar.
      expect(find.text('Mudanças recentes'), findsOneWidget);
      expect(find.text('Bia entrou no Grupo'), findsOneWidget);
      expect(find.textContaining('Não deu pra carregar'), findsNothing);
    },
  );

  testWidgets(
    'maior de idade participante encontra a entrada, e ela leva à conversa',
    (tester) async {
      await _pumpGroupDetail(tester, canSeeChat: true);

      expect(
        find.byTooltip('Conversa'),
        findsOneWidget,
        reason:
            'sem este contraste, apagar o botão para todo mundo deixaria o '
            'caso do menor verde',
      );

      await tester.tap(find.byTooltip('Conversa'));
      await tester.pumpAndSettle();

      expect(find.text('TELA_CONVERSA'), findsOneWidget);
    },
  );
}

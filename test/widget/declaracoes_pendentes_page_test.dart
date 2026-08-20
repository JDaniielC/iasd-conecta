import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/leadership/data/leadership_repository.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';
import 'package:iasd_conecta/features/leadership/leadership_providers.dart';
import 'package:iasd_conecta/features/leadership/presentation/pending_declarations_page.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

/// `PendingDeclarationsPage` — FR-004/FR-005: só o Administrador do distrito
/// decide, e nunca o Dono do Grupo. Estava em 2/51 linhas até a change
/// `cobertura-e-tdd`. Julgada na largura de celular (360).
///
/// O gate de Administrador mora na tela e não no `redirect` do router por um
/// motivo já medido (ver o comentário longo em pending_declarations_page.dart);
/// os testes abaixo cobrem os três estados desse gate — carregando, negado e
/// concedido — porque foi o estado "carregando" que passou despercebido na
/// primeira tentativa de conserto.

class MockLeadershipRepository extends Mock implements LeadershipRepository {}

LeadershipDeclaration _declaration(String id, {String groupId = 'g1'}) =>
    LeadershipDeclaration(
      id: id,
      groupId: groupId,
      userId: 'quem-declara',
      year: 2026,
      declaredAt: DateTime(2026, 2, 1),
    );

final _group = Group(
  id: 'g1',
  name: 'Ministério Jovem',
  category: 'Ministério Jovem',
  schedule: 'sábados 6h',
  location: 'Praça Central',
  ownerId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

Widget _app({
  required List<LeadershipDeclaration> pending,
  bool isAdmin = true,
  bool adminStillLoading = false,
  Object? adminError,
  Object? pendingError,
  LeadershipRepository? repository,
}) {
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('admin-1'),
      isDistrictAdminProvider.overrideWith((ref) async {
        if (adminError != null) throw adminError;
        // Future que nunca completa: é o instante da navegação, que é
        // exatamente onde o guarda de rota falhava.
        if (adminStillLoading) return Completer<bool>().future;
        return isAdmin;
      }),
      pendingDeclarationsProvider.overrideWith(
        (ref) async => pendingError != null ? throw pendingError : pending,
      ),
      groupProvider('g1').overrideWith((ref) async => _group),
      publicProfileProvider('quem-declara').overrideWith(
        (ref) async => const PublicProfile(id: 'quem-declara', displayName: 'Ana'),
      ),
      leadershipRepositoryProvider
          .overrideWithValue(repository ?? MockLeadershipRepository()),
    ],
    child: const MaterialApp(home: PendingDeclarationsPage()),
  );
}

Future<void> _pump(WidgetTester tester, Widget app, {bool settle = true}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(app);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('FR-004/FR-005: o gate de Administrador', () {
    testWidgets('enquanto a resposta não chega, a tela espera — não mostra a fila',
        (tester) async {
      await _pump(
        tester,
        _app(pending: [_declaration('d1')], adminStillLoading: true),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Confirmar'), findsNothing);
      expect(find.textContaining('Só o Administrador do distrito decide'), findsNothing);
    });

    testWidgets('quem não é Administrador vê a recusa e nenhum botão de decidir',
        (tester) async {
      await _pump(tester, _app(pending: [_declaration('d1')], isAdmin: false));

      expect(
        find.textContaining('Só o Administrador do distrito decide declarações'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Confirmar'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Rejeitar'), findsNothing);
    });

    testWidgets('a recusa aponta onde ver a própria declaração', (tester) async {
      await _pump(tester, _app(pending: const [], isAdmin: false));

      expect(
        find.textContaining('abra o Grupo/Ministério onde você se declarou'),
        findsOneWidget,
      );
    });

    testWidgets('falha ao descobrir se é Administrador nega, não libera',
        (tester) async {
      await _pump(
        tester,
        _app(pending: [_declaration('d1')], adminError: StateError('falha de rede')),
      );

      expect(
        find.textContaining('Só o Administrador do distrito decide'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Confirmar'), findsNothing);
    });
  });

  group('A fila do Administrador', () {
    testWidgets('cada pendência mostra Grupo, declarante e ano', (tester) async {
      await _pump(tester, _app(pending: [_declaration('d1')]));

      expect(find.text('Ministério Jovem'), findsOneWidget);
      expect(find.text('Declarante: Ana'), findsOneWidget);
      expect(find.text('Ano: 2026'), findsOneWidget);
    });

    testWidgets('fila vazia diz isso em vez de tela em branco', (tester) async {
      await _pump(tester, _app(pending: const []));

      expect(find.text('Nenhuma declaração pendente.'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('falha ao carregar a fila avisa, sem dizer que está vazia',
        (tester) async {
      await _pump(
        tester,
        _app(pending: const [], pendingError: StateError('falha de rede')),
      );

      expect(find.text('Não deu pra carregar as pendências.'), findsOneWidget);
      expect(find.text('Nenhuma declaração pendente.'), findsNothing);
    });
  });

  group('Decidir', () {
    testWidgets('Confirmar aprova a declaração daquele card', (tester) async {
      final repository = MockLeadershipRepository();
      when(() => repository.decide(
            declarationId: any(named: 'declarationId'),
            approve: any(named: 'approve'),
          )).thenAnswer((_) async {});

      await _pump(tester, _app(pending: [_declaration('d1')], repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await tester.pumpAndSettle();

      verify(() => repository.decide(declarationId: 'd1', approve: true)).called(1);
    });

    testWidgets('Rejeitar recusa a declaração daquele card', (tester) async {
      final repository = MockLeadershipRepository();
      when(() => repository.decide(
            declarationId: any(named: 'declarationId'),
            approve: any(named: 'approve'),
          )).thenAnswer((_) async {});

      await _pump(tester, _app(pending: [_declaration('d1')], repository: repository));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Rejeitar'));
      await tester.pumpAndSettle();

      verify(() => repository.decide(declarationId: 'd1', approve: false)).called(1);
    });

    testWidgets('decisão recusada pelo banco avisa em vez de sumir com o card',
        (tester) async {
      final repository = MockLeadershipRepository();
      when(() => repository.decide(
            declarationId: any(named: 'declarationId'),
            approve: any(named: 'approve'),
          )).thenThrow(StateError('recusado'));

      await _pump(tester, _app(pending: [_declaration('d1')], repository: repository));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('Não deu pra decidir agora. Tente de novo.'), findsOneWidget);
      // A pendência continua na fila — nada foi apresentado como decidido.
      expect(find.text('Declarante: Ana'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/data/actions_seen_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_list_page.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';

/// Marcador em memória: o teste não fala com o armazenamento do aparelho, e
/// muito menos com o servidor.
class FakeActionsSeenRepository implements ActionsSeenRepository {
  FakeActionsSeenRepository({this.stored});

  DateTime? stored;
  int writeCount = 0;

  @override
  Future<DateTime?> readLastSeenActionsDate() async => stored;

  @override
  Future<void> writeLastSeenActionsDate(DateTime date) async {
    stored = date;
    writeCount++;
  }
}

const _churches = [Church(id: 'igreja-1', name: 'Central')];

/// Quarta-feira. Fora da janela do Sábado adventista (sexta 17:30 a sábado
/// 17:30), pra nenhuma Ação virar "de Sábado" sem o teste pedir.
final _now = DateTime(2026, 8, 12, 12, 0);

/// Sexta 14/08/2026 às 19h — dentro da janela do Sábado.
final _duranteOSabado = DateTime(2026, 8, 14, 19, 0);

/// Quinta 20/08/2026 — futura e fora do Sábado.
final _foraDoSabado = DateTime(2026, 8, 20, 19, 0);

final _marcador = DateTime(2026, 8, 10, 8, 0);
final _antesDoMarcador = DateTime(2026, 8, 1, 8, 0);
final _depoisDoMarcador = DateTime(2026, 8, 11, 8, 0);

ActionWithChurch _action({
  required String id,
  required String name,
  required DateTime dateTime,
  String? groupId,
  DateTime? createdAt,
  bool isConfirmed = true,
}) {
  return ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: id,
      name: name,
      dateTime: dateTime,
      local: 'Templo',
      creatorId: 'dono-1',
      createdAt: createdAt ?? _antesDoMarcador,
      groupId: groupId,
      isConfirmed: isConfirmed,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ActionWithChurch> actions,
  Set<String> myGroupIds = const <String>{},
  FakeActionsSeenRepository? seen,
  bool hasProfile = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => hasProfile),
        actionsWithChurchProvider.overrideWith((ref) async => actions),
        churchesProvider.overrideWith((ref) async => _churches),
        clockProvider.overrideWithValue(() => _now),
        myGroupIdsProvider.overrideWith((ref) async => myGroupIds),
        actionsSeenRepositoryProvider
            .overrideWithValue(seen ?? FakeActionsSeenRepository(stored: _marcador)),
      ],
      child: const MaterialApp(home: ActionListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

const _forte = 'Aberta a todo o distrito';
const _neutro = 'Nova em um Grupo seu';

void main() {
  group('Ação avulsa entra sempre no destaque forte (5.1)', () {
    testWidgets('fora do Sábado', (tester) async {
      await _pump(tester, actions: [
        _action(id: 'a1', name: 'Visita Missionária', dateTime: _foraDoSabado),
      ]);

      expect(find.text(_forte), findsOneWidget);
      expect(find.text(_neutro), findsNothing);
      // Uma vez na faixa, outra na lista por período — a faixa não tira a
      // Ação de onde ela já estava.
      expect(find.text('Visita Missionária'), findsNWidgets(2));
    });

    testWidgets('no Sábado, sem perder a seção de Sábado', (tester) async {
      await _pump(tester, actions: [
        _action(id: 'a1', name: 'Culto de Adoração', dateTime: _duranteOSabado),
      ]);

      expect(find.text(_forte), findsOneWidget);
      expect(find.text('Sábado'), findsOneWidget);
      expect(find.text('Em destaque'), findsOneWidget);
      expect(find.text('Culto de Adoração'), findsNWidgets(2));
    });

    testWidgets('mesmo sem Perfil (Visitante)', (tester) async {
      await _pump(
        tester,
        hasProfile: false,
        actions: [_action(id: 'a1', name: 'Mutirão', dateTime: _foraDoSabado)],
      );

      expect(find.text(_forte), findsOneWidget);
    });
  });

  group('Ação de Grupo só entra pra quem participa e só enquanto nova (5.2)', () {
    testWidgets('Grupo que participo, criada depois do marcador: destaque neutro',
        (tester) async {
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        actions: [
          _action(
            id: 'a1',
            name: 'Ensaio do Coral',
            dateTime: _foraDoSabado,
            groupId: 'g1',
            createdAt: _depoisDoMarcador,
          ),
        ],
      );

      expect(find.text(_neutro), findsOneWidget);
      expect(find.text(_forte), findsNothing);
      expect(find.text('Ensaio do Coral'), findsNWidgets(2));
    });

    testWidgets('a mesma Ação some do destaque na abertura seguinte', (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador);
      final acoes = [
        _action(
          id: 'a1',
          name: 'Ensaio do Coral',
          dateTime: _foraDoSabado,
          groupId: 'g1',
          createdAt: _depoisDoMarcador,
        ),
      ];

      await _pump(tester, actions: acoes, myGroupIds: const {'g1'}, seen: seen);
      expect(find.text(_neutro), findsOneWidget);
      // Abrir a tela avançou o marcador — é isso que consome a novidade.
      expect(seen.writeCount, 1);
      expect(seen.stored, _now);

      // Desmontar de verdade entre as duas aberturas: `pumpWidget` com a
      // mesma `ActionListPage` na mesma posição reaproveita o `State`, e o
      // `initState` que lê o marcador não rodaria de novo — o teste passaria
      // a medir cache de widget, não a regra.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await _pump(tester, actions: acoes, myGroupIds: const {'g1'}, seen: seen);
      expect(find.text(_neutro), findsNothing);
      expect(find.text('Ensaio do Coral'), findsOneWidget);
    });

    testWidgets('Grupo que participo, criada antes do marcador: sem destaque',
        (tester) async {
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        actions: [
          _action(
            id: 'a1',
            name: 'Ensaio do Coral',
            dateTime: _foraDoSabado,
            groupId: 'g1',
            createdAt: _antesDoMarcador,
          ),
        ],
      );

      expect(find.text(_neutro), findsNothing);
      expect(find.text('Ensaio do Coral'), findsOneWidget);
    });

    testWidgets('Grupo que NÃO participo nunca entra, mesmo recém-criada',
        (tester) async {
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        actions: [
          _action(
            id: 'a1',
            name: 'Reunião do Clube',
            dateTime: _foraDoSabado,
            groupId: 'outro-grupo',
            createdAt: _depoisDoMarcador,
          ),
        ],
      );

      expect(find.text('Em destaque'), findsNothing);
      expect(find.text('Reunião do Clube'), findsOneWidget);
    });

    testWidgets('instalação nova (sem marcador) não avisa nada de Grupo',
        (tester) async {
      final seen = FakeActionsSeenRepository();
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        seen: seen,
        actions: [
          _action(
            id: 'a1',
            name: 'Ensaio do Coral',
            dateTime: _foraDoSabado,
            groupId: 'g1',
            createdAt: _depoisDoMarcador,
          ),
        ],
      );

      expect(find.text(_neutro), findsNothing);
      // Mas o marcador já nasce gravado, senão a primeira Ação real nunca
      // seria nova.
      expect(seen.stored, _now);
    });

    testWidgets('candidata em votação não entra no destaque', (tester) async {
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        actions: [
          _action(
            id: 'a1',
            name: 'Candidata em votação',
            dateTime: _foraDoSabado,
            groupId: 'g1',
            createdAt: _depoisDoMarcador,
            isConfirmed: false,
          ),
        ],
      );

      expect(find.text('Em destaque'), findsNothing);
    });
  });

  group('fechar um item vale só pra ele, e só nesta sessão (5.3)', () {
    testWidgets('fechar remove da faixa sem afetar os demais', (tester) async {
      await _pump(tester, actions: [
        _action(id: 'a1', name: 'Visita Missionária', dateTime: _foraDoSabado),
        _action(id: 'a2', name: 'Mutirão de Limpeza', dateTime: _foraDoSabado),
      ]);

      expect(find.text(_forte), findsNWidgets(2));
      expect(find.text('Visita Missionária'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Tirar do destaque').first);
      await tester.pumpAndSettle();

      // Some da faixa, continua na lista por período.
      expect(find.text(_forte), findsOneWidget);
      expect(find.text('Visita Missionária'), findsOneWidget);
      expect(find.text('Mutirão de Limpeza'), findsNWidgets(2));
    });

    testWidgets('fechar o único item tira a faixa inteira sem quebrar a tela',
        (tester) async {
      await _pump(tester, actions: [
        _action(id: 'a1', name: 'Visita Missionária', dateTime: _foraDoSabado),
      ]);

      await tester.tap(find.byTooltip('Tirar do destaque'));
      await tester.pumpAndSettle();

      expect(find.text('Em destaque'), findsNothing);
      expect(find.text('Visita Missionária'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('em vários Grupos, a faixa traz a Ação nova de cada um', (tester) async {
    await _pump(
      tester,
      myGroupIds: const {'g1', 'g2', 'g3'},
      actions: [
        _action(
          id: 'a1',
          name: 'Ensaio do Coral',
          dateTime: _foraDoSabado,
          groupId: 'g1',
          createdAt: _depoisDoMarcador,
        ),
        _action(
          id: 'a2',
          name: 'Reunião do Clube',
          dateTime: _foraDoSabado,
          groupId: 'g2',
          createdAt: _depoisDoMarcador,
        ),
        // Grupo meu, mas Ação antiga: não é novidade nenhuma.
        _action(
          id: 'a3',
          name: 'Estudo Bíblico',
          dateTime: _foraDoSabado,
          groupId: 'g3',
          createdAt: _antesDoMarcador,
        ),
      ],
    );

    expect(find.text(_neutro), findsNWidgets(2));
    // Ela continua na lista por período — só está abaixo da dobra, que a
    // faixa empurrou para baixo, e `find` não acha o que o `ListView` ainda
    // não construiu.
    await tester.scrollUntilVisible(find.text('Estudo Bíblico'), 200);
    expect(find.text('Estudo Bíblico'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lista sem nenhuma Ação em destaque não abre a faixa', (tester) async {
    await _pump(
      tester,
      myGroupIds: const <String>{},
      actions: [
        _action(
          id: 'a1',
          name: 'Reunião do Clube',
          dateTime: _foraDoSabado,
          groupId: 'g1',
          createdAt: _depoisDoMarcador,
        ),
      ],
    );

    expect(find.text('Em destaque'), findsNothing);
    expect(find.text('Reunião do Clube'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

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
  FakeActionsSeenRepository({
    this.stored,
    this.failWrite = false,
    this.failRead = false,
  });

  DateTime? stored;
  int writeCount = 0;

  /// Armazenamento do aparelho recusando a gravação.
  final bool failWrite;

  /// Armazenamento do aparelho recusando a leitura.
  final bool failRead;

  @override
  Future<DateTime?> readLastSeenActionsDate() async {
    if (failRead) throw Exception('armazenamento indisponível');
    return stored;
  }

  @override
  Future<void> writeLastSeenActionsDate(DateTime date) async {
    writeCount++;
    if (failWrite) throw Exception('armazenamento indisponível');
    stored = date;
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
  DateTime? cancelledAt,
}) {
  return ActionWithChurch(
    churchId: 'igreja-1',
    action: Action(
      id: id,
      name: name,
      dateTime: dateTime,
      location: 'Templo',
      creatorId: 'dono-1',
      createdAt: createdAt ?? _antesDoMarcador,
      groupId: groupId,
      isConfirmed: isConfirmed,
      cancelledAt: cancelledAt,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ActionWithChurch> actions,
  Set<String> myGroupIds = const <String>{},
  FakeActionsSeenRepository? seen,
  bool hasProfile = true,
  bool failList = false,
  bool failGroups = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => hasProfile),
        actionsWithChurchProvider.overrideWith((ref) async {
          if (failList) throw Exception('sem rede');
          return actions;
        }),
        churchesProvider.overrideWith((ref) async => _churches),
        clockProvider.overrideWithValue(() => _now),
        myGroupIdsProvider.overrideWith((ref) async {
          if (failGroups) throw Exception('sem rede');
          return myGroupIds;
        }),
        actionsSeenRepositoryProvider
            .overrideWithValue(seen ?? FakeActionsSeenRepository(stored: _marcador)),
      ],
      child: const MaterialApp(home: ActionListPage()),
    ),
  );
  await tester.pumpAndSettle();
}

const _forte = 'Todo o distrito';
const _neutro = 'Novo no seu Grupo';

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

  group('Ação cancelada não sobe para o destaque', () {
    testWidgets('nem sendo avulsa — mas continua na lista por período',
        (tester) async {
      await _pump(tester, actions: [
        _action(
          id: 'a1',
          name: 'Visita Missionária',
          dateTime: _foraDoSabado,
          cancelledAt: _depoisDoMarcador,
        ),
      ]);

      expect(find.text('Em destaque'), findsNothing);
      expect(find.text('Visita Missionária'), findsOneWidget);
      expect(find.textContaining('Cancelada'), findsOneWidget);
    });

    testWidgets('nem sendo Ação nova de um Grupo meu', (tester) async {
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
            cancelledAt: _depoisDoMarcador,
          ),
        ],
      );

      expect(find.text('Em destaque'), findsNothing);
      expect(find.text('Ensaio do Coral'), findsOneWidget);
    });
  });

  group('a faixa para em 3 cartões', () {
    List<ActionWithChurch> avulsas(int quantas) => [
          for (var i = 1; i <= quantas; i++)
            _action(
              id: 'a$i',
              name: 'Ação $i',
              dateTime: _foraDoSabado.add(Duration(days: i)),
            ),
        ];

    testWidgets('com 5 avulsas mostra 3 e oferece ver o resto', (tester) async {
      await _pump(tester, actions: avulsas(5));

      expect(find.text(_forte), findsNWidgets(3));
      // Três cartões já ocupam a altura da viewport do teste — o botão fica
      // logo abaixo dela. É esse o ponto do corte: a lista por período passa
      // a estar a uma rolada curta, e não vinte cartões abaixo.
      await tester.scrollUntilVisible(find.text('Ver mais 2 em destaque'), 100);
      expect(find.text('Ver mais 2 em destaque'), findsOneWidget);
    });

    testWidgets('"ver mais" abre a faixa inteira e volta atrás', (tester) async {
      // Tela alta de propósito: este teste é sobre o que a faixa contém,
      // não sobre o que cabe na dobra. Na viewport padrão cada `tap` empurra
      // o botão para fora da tela e o teste vira uma sequência de rolagens
      // que não prova nada sobre a regra.
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, actions: avulsas(5));

      // Fechada: 3 na faixa, e a 5ª só existe na lista por período.
      expect(find.text(_forte), findsNWidgets(3));
      expect(find.text('Ação 5'), findsOneWidget);

      await tester.tap(find.text('Ver mais 2 em destaque'));
      await tester.pumpAndSettle();

      expect(find.text(_forte), findsNWidgets(5));
      expect(find.text('Ação 5'), findsNWidgets(2));

      await tester.tap(find.text('Ver menos'));
      await tester.pumpAndSettle();

      expect(find.text(_forte), findsNWidgets(3));
      expect(find.text('Ver mais 2 em destaque'), findsOneWidget);
    });

    testWidgets('com 4 avulsas o texto vai para o singular', (tester) async {
      await _pump(tester, actions: avulsas(4));

      await tester.scrollUntilVisible(find.text('Ver mais 1 em destaque'), 100);
      expect(find.text('Ver mais 1 em destaque'), findsOneWidget);
    });

    testWidgets('com 3 avulsas não aparece botão nenhum', (tester) async {
      await _pump(tester, actions: avulsas(3));

      expect(find.text(_forte), findsNWidgets(3));
      expect(find.textContaining('Ver mais'), findsNothing);
      expect(find.text('Ver menos'), findsNothing);
    });

    testWidgets('fechar um dos 4 primeiros promove o que estava escondido',
        (tester) async {
      await _pump(tester, actions: avulsas(4));

      expect(find.text('Ação 4'), findsNothing);

      await tester.tap(find.byTooltip('Tirar do destaque').first);
      await tester.pumpAndSettle();

      // Sobraram 3: a quarta subiu para a faixa e o botão saiu de cena.
      expect(find.text(_forte), findsNWidgets(3));
      expect(find.text('Ação 4'), findsWidgets);
      expect(find.textContaining('Ver mais'), findsNothing);
    });
  });

  testWidgets('novidade de Grupo vem antes das avulsas, mesmo sendo a mais distante',
      (tester) async {
    // Achado no navegador em 2026-08-12: a faixa herdava a ordenação por data
    // da lista, e a única Ação nova de um Grupo caiu em 6º — escondida atrás
    // do "ver mais". Era a única que a pessoa não tinha como saber que
    // existia; as avulsas ela vê todo dia.
    await _pump(
      tester,
      myGroupIds: const {'g1'},
      actions: [
        for (var i = 1; i <= 4; i++)
          _action(
            id: 'avulsa$i',
            name: 'Avulsa $i',
            dateTime: _foraDoSabado.add(Duration(days: i)),
          ),
        _action(
          id: 'nova',
          name: 'Cantata de Natal',
          // A mais distante de todas: por data seria a última da faixa.
          dateTime: _foraDoSabado.add(const Duration(days: 30)),
          groupId: 'g1',
          createdAt: _depoisDoMarcador,
        ),
      ],
    );

    expect(find.text(_neutro), findsOneWidget);
    final novidade = tester.getTopLeft(find.text('Cantata de Natal')).dy;
    final primeiraAvulsa = tester.getTopLeft(find.text('Avulsa 1').first).dy;
    expect(novidade, lessThan(primeiraAvulsa),
        reason: 'a novidade de Grupo tem que abrir a faixa, não fechá-la');
  });

  testWidgets('sair da tela e voltar também consome a novidade', (tester) async {
    // O bug de 2026-08-12, achado no navegador e não em teste: enquanto isto
    // vivia no `initState`, navegar /acoes -> /grupos -> /acoes NÃO avançava o
    // marcador. `lib/app.dart` constrói `const ActionListPage()`, o widget é
    // idêntico entre navegações, o Flutter reusa o `State` e o `initState` só
    // roda no arranque frio — a mesma Ação de Grupo ficava "nova" para sempre
    // naquela sessão do app.
    //
    // O `ProviderScope` é UM só nas duas visitas, de propósito: é o que
    // reproduz continuar no mesmo app. Trocar de cena e voltar é o que faz o
    // provider `autoDispose` morrer e renascer.
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
    final mostrarAcoes = ValueNotifier<bool>(true);
    addTearDown(mostrarAcoes.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hasProfileProvider.overrideWith((ref) async => true),
          actionsWithChurchProvider.overrideWith((ref) async => acoes),
          churchesProvider.overrideWith((ref) async => _churches),
          clockProvider.overrideWithValue(() => _now),
          myGroupIdsProvider.overrideWith((ref) async => const {'g1'}),
          actionsSeenRepositoryProvider.overrideWithValue(seen),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: mostrarAcoes,
            builder: (context, mostrando, _) =>
                mostrando ? const ActionListPage() : const Scaffold(body: Text('outra tela')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_neutro), findsOneWidget);
    expect(seen.writeCount, 1);

    // Saiu para outra tela e voltou — sem reiniciar o app.
    mostrarAcoes.value = false;
    await tester.pumpAndSettle();
    mostrarAcoes.value = true;
    await tester.pumpAndSettle();

    expect(seen.writeCount, 2, reason: 'voltar para a tela precisa avançar o marcador');
    expect(find.text(_neutro), findsNothing,
        reason: 'a Ação já foi vista na primeira visita, não é mais novidade');
    expect(find.text('Ensaio do Coral'), findsOneWidget);
  });

  testWidgets('num celular a faixa cheia não empurra a lista para fora da dobra',
      (tester) async {
    // iPhone 14 em pixels lógicos. Esta é a tela que importa: o app é usado no
    // celular, e a faixa foi desenhada num monitor largo onde o problema não
    // aparecia. Com o cartão cheio da lista (~148px cada) três destaques mais
    // a barra de filtro passavam de 844 e o primeiro cabeçalho de período
    // nascia fora da tela.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, actions: [
      for (var i = 1; i <= 5; i++)
        _action(
          id: 'a$i',
          name: 'Ação $i',
          dateTime: _foraDoSabado.add(Duration(days: i)),
        ),
    ]);

    expect(find.text(_forte), findsNWidgets(3));
    // O cabeçalho do primeiro período precisa estar dentro dos 844 — não só
    // construído pelo `ListView`, que constrói um tanto além da dobra.
    final cabecalho = tester.getTopLeft(find.text('Outras datas')).dy;
    expect(cabecalho, lessThan(844),
        reason: 'a faixa empurrou a lista por período para fora da tela do celular');
  });

  group('o marcador só avança quando a tela teve o que mostrar', () {
    testWidgets('lista que não carrega não consome a novidade', (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador);
      await _pump(tester, actions: const [], seen: seen, failList: true);

      expect(find.textContaining('Não deu pra carregar'), findsOneWidget);
      // O defeito medido em 2026-08-12: aqui gravava, e uma falha de rede de
      // um segundo apagava a novidade de todos os Grupos para sempre.
      expect(seen.writeCount, 0);
      expect(seen.stored, _marcador);
    });

    testWidgets('consulta de Grupos que não carrega não consome a novidade',
        (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador);
      await _pump(
        tester,
        seen: seen,
        failGroups: true,
        actions: [_action(id: 'a1', name: 'Mutirão', dateTime: _foraDoSabado)],
      );

      // A faixa não quebra: Ação avulsa não depende de saber os meus Grupos.
      expect(find.text(_forte), findsOneWidget);
      // Mas sem saber quais Grupos são os meus, não houve como mostrar a
      // novidade deles — então ela não foi consumida.
      expect(seen.writeCount, 0);
      expect(seen.stored, _marcador);
    });

    testWidgets('lista vazia avança o marcador — não há novidade a perder',
        (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador);
      await _pump(tester, actions: const [], seen: seen);

      expect(seen.writeCount, 1);
      expect(seen.stored, _now);
    });

    testWidgets('falha ao ler o marcador não o sobrescreve', (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador, failRead: true);
      await _pump(
        tester,
        myGroupIds: const {'g1'},
        seen: seen,
        actions: [_action(id: 'a1', name: 'Mutirão', dateTime: _foraDoSabado)],
      );

      // Sem saber até quando a pessoa já viu, gravar `agora` por cima
      // apagaria a fronteira e toda Ação existente deixaria de ser nova de uma
      // vez. Melhor não mexer e tentar de novo na próxima abertura.
      expect(seen.writeCount, 0);
      expect(seen.stored, _marcador);
      // A faixa continua servindo o que não depende do marcador.
      expect(find.text(_forte), findsOneWidget);
    });

    testWidgets('falha ao gravar não derruba o destaque já lido', (tester) async {
      final seen = FakeActionsSeenRepository(stored: _marcador, failWrite: true);
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

      // Ler e gravar viviam no mesmo Future: a falha da gravação descartava a
      // leitura boa e a faixa perdia o destaque de Grupo inteiro, calada.
      expect(find.text(_neutro), findsOneWidget);
      expect(seen.stored, _marcador, reason: 'o marcador não pode se perder');
    });
  });

  testWidgets('filtro de Igreja não esconde a novidade de um Grupo meu',
      (tester) async {
    await _pump(
      tester,
      myGroupIds: const {'g1'},
      actions: [
        _action(id: 'a1', name: 'Avulsa da Central', dateTime: _foraDoSabado),
        ActionWithChurch(
          churchId: 'igreja-2',
          action: Action(
            id: 'g1a',
            name: 'Ensaio do Coral',
            dateTime: _foraDoSabado,
            location: 'Templo',
            creatorId: 'dono-1',
            createdAt: _depoisDoMarcador,
            groupId: 'g1',
          ),
        ),
      ],
    );

    expect(find.text(_neutro), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Central').last);
    await tester.pumpAndSettle();

    // Participação não filtra por Igreja, e o que a faixa mostra também não:
    // filtrando, a novidade do meu Grupo de outra Igreja continua na faixa...
    expect(find.text(_neutro), findsOneWidget);
    // ...e sai só da lista por período, que é o que o filtro existe para
    // recortar.
    expect(find.text('Ensaio do Coral'), findsOneWidget);
  });

  testWidgets('participar de um Grupo e voltar já mostra a novidade dele',
      (tester) async {
    // Medido em 2026-08-13, antes de `myGroupIdsProvider` virar `autoDispose`:
    // participar e voltar para /acoes na mesma sessão dava `neutro=0` e nem
    // refazia a consulta — e o marcador avançava assim mesmo, porque a lista e
    // os Grupos "carregaram com sucesso" respondendo a pergunta de antes. A
    // novidade era consumida sem nunca ter sido mostrada, e nem reiniciar o
    // app a trazia de volta.
    var meusGrupos = <String>{};
    var consultas = 0;
    final seen = FakeActionsSeenRepository(stored: _marcador);
    final naTelaDeAcoes = ValueNotifier<bool>(true);
    addTearDown(naTelaDeAcoes.dispose);
    // Criada depois de `_now`, que é quando a primeira visita avança o
    // marcador. Ação que já existia ANTES de a pessoa entrar no Grupo é outro
    // caso, e continua sem aparecer — ver a limitação registrada em
    // `design.md` sobre o marcador único.
    final criadaEnquantoEuEntrava = _now.add(const Duration(minutes: 1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hasProfileProvider.overrideWith((ref) async => true),
          actionsWithChurchProvider.overrideWith((ref) async => [
                _action(
                  id: 'g1a',
                  name: 'Ensaio do Coral',
                  dateTime: _foraDoSabado,
                  groupId: 'g1',
                  createdAt: criadaEnquantoEuEntrava,
                ),
              ]),
          churchesProvider.overrideWith((ref) async => _churches),
          clockProvider.overrideWithValue(() => _now),
          myGroupIdsProvider.overrideWith((ref) async {
            consultas++;
            return meusGrupos;
          }),
          actionsSeenRepositoryProvider.overrideWithValue(seen),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: naTelaDeAcoes,
            builder: (context, emAcoes, _) => emAcoes
                ? const ActionListPage()
                : const Scaffold(body: Text('tela do Grupo')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_neutro), findsNothing);
    expect(consultas, 1);

    // Foi à tela do Grupo, tocou em Participar, e voltou — mesma sessão do
    // app, sem reiniciar nada.
    naTelaDeAcoes.value = false;
    await tester.pumpAndSettle();
    meusGrupos = {'g1'};
    naTelaDeAcoes.value = true;
    await tester.pumpAndSettle();

    expect(consultas, 2, reason: 'voltar para a tela tem que perguntar de novo');
    expect(find.text(_neutro), findsOneWidget);
  });

  testWidgets('item fechado reaparece depois de reiniciar o app', (tester) async {
    final acoes = [_action(id: 'a1', name: 'Mutirão', dateTime: _foraDoSabado)];
    await _pump(tester, actions: acoes);
    expect(find.text(_forte), findsOneWidget);

    await tester.tap(find.byTooltip('Tirar do destaque'));
    await tester.pumpAndSettle();
    expect(find.text(_forte), findsNothing);

    // `ProviderScope` novo é o processo novo do app: o dismiss vive só em
    // memória, então tem que morrer aqui. Reaparecer é o comportamento
    // querido, não um bug a consertar.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _pump(tester, actions: acoes);

    expect(find.text(_forte), findsOneWidget);
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

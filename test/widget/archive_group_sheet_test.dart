import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/group/data/group_repository.dart';
import 'package:iasd_conecta/features/group/domain/archive_preview.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/group/presentation/archive_group_sheet.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';
import 'package:iasd_conecta/features/leadership/leadership_providers.dart';
import 'package:mocktail/mocktail.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

const _groupId = 'grupo-1';

Future<void> pumpSheet(
  WidgetTester tester, {
  required ArchivePreview preview,
  GroupRepository? repo,
  List<LeadershipDeclaration> leaders = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) groupRepositoryProvider.overrideWithValue(repo),
        archivePreviewProvider(_groupId).overrideWith((ref) async => preview),
        currentLeadersProvider(_groupId).overrideWith((ref) async => leaders),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ArchiveGroupSheet(groupId: _groupId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockGroupRepository repo;

  setUp(() {
    repo = MockGroupRepository();
    when(() => repo.archiveGroup(any())).thenAnswer((_) async {});
  });

  testWidgets(
    'FR-003/SC-001: a confirmação mostra os quatro números reais',
    (tester) async {
      await pumpSheet(
        tester,
        preview: const ArchivePreview(
          futureActions: 2,
          confirmedAttendances: 12,
          openVotingRounds: 1,
          members: 8,
        ),
      );

      // Não é "2 Ações" no vácuo — é "2 Ações, com 12 pessoas que já tinham
      // dito sim". O segundo número é o que faz a decisão ser informada.
      expect(find.textContaining('2 Ações marcadas são canceladas'),
          findsOneWidget);
      expect(find.textContaining('12 pessoas'), findsOneWidget);
      expect(find.textContaining('1 Rodada de votação é encerrada'),
          findsOneWidget);
      expect(find.textContaining('8 pessoas deixam de participar'),
          findsOneWidget);
    },
  );

  testWidgets(
    'FR-004: com tudo zerado, diz em palavras que nada será perdido',
    (tester) async {
      await pumpSheet(
        tester,
        preview: const ArchivePreview(
          futureActions: 0,
          confirmedAttendances: 0,
          openVotingRounds: 0,
          members: 3,
        ),
      );

      expect(find.textContaining('Nada será perdido'), findsOneWidget);
      // Quatro zeros obrigariam a pessoa a interpretar números antes de uma
      // ação irreversível — que é onde o erro acontece.
      expect(find.textContaining('0 Ações'), findsNothing);
    },
  );

  testWidgets(
    'FR-005: Ministério com Líder confirmado ganha o aviso extra',
    (tester) async {
      await pumpSheet(
        tester,
        preview: const ArchivePreview(
          futureActions: 1,
          confirmedAttendances: 4,
          openVotingRounds: 0,
          members: 5,
        ),
        leaders: [
          LeadershipDeclaration(
            id: 'lid-1',
            groupId: _groupId,
            userId: 'uid-1',
            year: 2026,
            declaredAt: DateTime.utc(2026, 1, 10),
            confirmedAt: DateTime.utc(2026, 1, 11),
          ),
        ],
      );

      expect(
        find.textContaining('identificação pública do Líder/Diretor'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'FR-006/SC-002: desistir não dispara chamada nenhuma',
    (tester) async {
      await pumpSheet(
        tester,
        preview: const ArchivePreview(
          futureActions: 2,
          confirmedAttendances: 12,
          openVotingRounds: 1,
          members: 8,
        ),
        repo: repo,
      );

      await tester.tap(find.text('Desistir'));
      await tester.pumpAndSettle();

      // A prévia é só leitura, então desistir não tem o que desfazer — mas o
      // teste existe para que continue assim.
      verifyNever(() => repo.archiveGroup(any()));
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/cover_photo/cover_photo_providers.dart';
import 'package:iasd_conecta/features/cover_photo/data/cover_photo_repository.dart';
import 'package:iasd_conecta/features/district_admin/district_admin_providers.dart';
import 'package:iasd_conecta/features/image_report/domain/image_report.dart';
import 'package:iasd_conecta/features/image_report/image_report_providers.dart';
import 'package:iasd_conecta/features/image_report/presentation/pending_reports_page.dart';
import 'package:mocktail/mocktail.dart';

class MockCoverPhotoRepository extends Mock implements CoverPhotoRepository {}

ReportedImage buildReported({
  String photoId = 'capa-1',
  int count = 1,
  List<String> reasons = const ['Aparece uma criança'],
}) {
  return ReportedImage(
    photoId: photoId,
    reportCount: count,
    reasons: reasons,
    groupId: 'grupo-1',
    actionId: null,
    path: 'grupo/grupo-1/x.jpg',
  );
}

Future<void> pumpPage(
  WidgetTester tester, {
  required bool isDistrictAdmin,
  List<ReportedImage> pending = const [],
}) async {
  final coverRepository = MockCoverPhotoRepository();
  when(() => coverRepository.publicUrlForPath(any()))
      .thenReturn('http://127.0.0.1/inexistente.jpg');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coverPhotoRepositoryProvider.overrideWithValue(coverRepository),
        isDistrictAdminProvider.overrideWith((ref) async => isDistrictAdmin),
        pendingReportedImagesProvider.overrideWith((ref) async => pending),
      ],
      child: const MaterialApp(home: PendingReportsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('FR-018: pendências agrupadas por IMAGEM, não por denúncia', () {
    testWidgets('duas denúncias sobre a mesma imagem são um item com contagem',
        (tester) async {
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        pending: [
          buildReported(
            count: 2,
            reasons: ['Aparece uma criança', 'Foto de pessoa'],
          ),
        ],
      );

      // Um card, não dois. Sem isso, uma imagem que incomodou muita gente
      // enterraria as outras pendências.
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('2 denúncias'), findsOneWidget);
      // Os dois motivos aparecem — o Administrador precisa deles para julgar.
      expect(find.text('• Aparece uma criança'), findsOneWidget);
      expect(find.text('• Foto de pessoa'), findsOneWidget);
    });

    testWidgets('uma denúncia usa o singular', (tester) async {
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        pending: [buildReported()],
      );
      expect(find.text('1 denúncia'), findsOneWidget);
    });

    testWidgets('lista vazia se explica', (tester) async {
      await pumpPage(tester, isDistrictAdmin: true);
      expect(find.text('Nenhuma imagem denunciada.'), findsOneWidget);
    });

    testWidgets('resolver oferece os dois caminhos, e os dois tiram da lista',
        (tester) async {
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        pending: [buildReported()],
      );
      expect(find.text('Remover imagem'), findsOneWidget);
      expect(find.text('Improcedente'), findsOneWidget);
    });
  });

  group('FR-020/SC-008: a identidade de quem denunciou não vaza', () {
    testWidgets('Usuário comum não vê a lista, e a tela diz o que fazer',
        (tester) async {
      await pumpPage(
        tester,
        isDistrictAdmin: false,
        pending: [buildReported()],
      );

      // A lição da feature 018: a tela precisa DIZER algo, não só esconder.
      // Antes, quem chegasse por URL via a lista e clicava em botões que o
      // banco recusava, sem retorno nenhum.
      expect(find.textContaining('Só o Administrador do distrito'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Remover imagem'), findsNothing);
    });

    testWidgets('nem para o Administrador a tela mostra quem denunciou',
        (tester) async {
      await pumpPage(
        tester,
        isDistrictAdmin: true,
        pending: [buildReported()],
      );

      // `ReportedImage` nem carrega o autor: a consulta do repositório não
      // pede a coluna. O que a tela não recebe, a tela não vaza.
      expect(find.textContaining('Denunciado por'), findsNothing);
      expect(find.textContaining('denunciante'), findsNothing);
    });
  });
}

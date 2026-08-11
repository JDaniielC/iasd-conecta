import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/image_report/data/image_report_repository.dart';
import 'package:iasd_conecta/features/image_report/image_report_providers.dart';
import 'package:iasd_conecta/features/image_report/presentation/report_image_sheet.dart';
import 'package:mocktail/mocktail.dart';

class MockImageReportRepository extends Mock
    implements ImageReportRepository {}

/// FR-015 — **quem não tem cadastro consegue denunciar.**
///
/// Este arquivo existe por causa de um bug medido, e a lição vale mais que o
/// teste: o app faz `signInAnonymously` na inicialização, então **todo
/// Visitante tem `currentUser`**. A primeira versão do repositório mandava
/// esse id como `denunciante_id`, e o insert batia na FK contra `perfis`:
///
///   23503 ... violates foreign key constraint
///   "denuncias_imagem_denunciante_id_fkey"
///
/// O teste de integração passava, porque usava `set role anon` — uma sessão
/// que o app nunca tem. Ele provava o banco, não o app.
///
/// **Ter sessão não é ter Perfil**, e **ser anônimo não é não ter Perfil**: o
/// app permite Perfil sem Conta desde a feature 001. O único sinal correto é
/// `hasProfileProvider`.
Future<void> pumpSheet(
  WidgetTester tester, {
  required bool hasProfile,
  required ImageReportRepository repository,
  String? currentUserId = 'usuario-1',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageReportRepositoryProvider.overrideWithValue(repository),
        hasProfileProvider.overrideWith((ref) async => hasProfile),
        currentUserIdProvider.overrideWithValue(currentUserId),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ReportImageSheet(photoId: 'capa-1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late MockImageReportRepository repository;

  setUp(() {
    repository = MockImageReportRepository();
    when(() => repository.report(
          photoId: any(named: 'photoId'),
          reason: any(named: 'reason'),
          reporterId: any(named: 'reporterId'),
        )).thenAnswer((_) async {});
  });

  testWidgets(
    'Visitante COM sessão anônima e SEM Perfil denuncia, e a denúncia vai sem autor',
    (tester) async {
      // O caso que motivou a feature inteira: a mãe sem cadastro pedindo a
      // retirada da foto da filha. Ela TEM currentUser — o app assinou a
      // sessão anônima por ela — e não tem linha em `perfis`.
      await pumpSheet(
        tester,
        hasProfile: false,
        repository: repository,
        currentUserId: 'sessao-anonima-sem-perfil',
      );

      await tester.enterText(find.byType(TextField), 'Aparece minha filha');
      await tester.tap(find.text('Enviar denúncia'));
      await tester.pumpAndSettle();

      final captured = verify(() => repository.report(
            photoId: 'capa-1',
            reason: 'Aparece minha filha',
            reporterId: captureAny(named: 'reporterId'),
          )).captured;
      expect(captured.single, isNull,
          reason: 'mandar o id da sessão anônima viola a FK contra perfis');
    },
  );

  testWidgets('quem TEM Perfil assina a denúncia', (tester) async {
    await pumpSheet(
      tester,
      hasProfile: true,
      repository: repository,
      currentUserId: 'usuario-com-perfil',
    );

    await tester.enterText(find.byType(TextField), 'Foto de pessoa');
    await tester.tap(find.text('Enviar denúncia'));
    await tester.pumpAndSettle();

    verify(() => repository.report(
          photoId: 'capa-1',
          reason: 'Foto de pessoa',
          reporterId: 'usuario-com-perfil',
        )).called(1);
  });

  testWidgets('motivo vazio não vira denúncia', (tester) async {
    await pumpSheet(tester, hasProfile: false, repository: repository);

    await tester.tap(find.text('Enviar denúncia'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Escreva em uma frase'), findsOneWidget);
    verifyNever(() => repository.report(
          photoId: any(named: 'photoId'),
          reason: any(named: 'reason'),
          reporterId: any(named: 'reporterId'),
        ));
  });
}

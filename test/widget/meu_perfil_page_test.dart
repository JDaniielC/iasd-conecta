import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/profile/data/profile_repository.dart';
import 'package:iasd_conecta/features/profile/domain/church.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:iasd_conecta/features/profile/presentation/my_profile_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

const testChurch = Church(id: 'igreja-1', name: 'Igreja Teste');
const otherChurch = Church(id: 'igreja-2', name: 'Outra Igreja');

Profile buildProfile({
  String name = 'Ana Souza',
  String? nickname = 'Aninha',
  String? churchId,
  String? phone = '81999990000',
  Gender? gender = Gender.female,
  int? age = 30,
  DateTime? churchConsentAt,
}) {
  return Profile(
    name: name,
    gender: gender,
    age: age,
    lgpdConsentAccepted: true,
    nickname: nickname,
    churchId: churchId,
    phone: phone,
    churchLgpdConsentAccepted: churchId != null,
    lgpdConsentAcceptedAt: DateTime.utc(2026, 7, 25, 12),
    churchLgpdConsentAcceptedAt: churchConsentAt,
  );
}

Future<void> pumpMyProfilePage(
  WidgetTester tester, {
  required Profile profile,
  ProfileRepository? repo,
  List<Church> churches = const <Church>[testChurch, otherChurch],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repo != null) profileRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith((ref) async => profile),
        churchesProvider.overrideWith((ref) async => churches),
      ],
      child: const MaterialApp(home: MyProfilePage()),
    ),
  );
  await tester.pumpAndSettle();
}

ElevatedButton saveButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byType(ElevatedButton));

void main() {
  late MockProfileRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const Profile(
        name: '',
        gender: Gender.female,
        age: 0,
        lgpdConsentAccepted: false,
      ),
    );
  });

  setUp(() {
    repo = MockProfileRepository();
    when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});
  });

  testWidgets(
    'FR-001/FR-002/SC-001: os sete campos aparecem com os rótulos do glossário',
    (tester) async {
      await pumpMyProfilePage(
        tester,
        profile: buildProfile(
          churchId: testChurch.id,
          churchConsentAt: DateTime.utc(2026, 8, 1),
        ),
      );

      for (final label in [
        'Nome',
        'Apelido',
        'Igreja de origem',
        'Telefone',
        'Gênero',
        'Idade',
        'Consentimento aceito em',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Feminino'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      // Data legível, não ISO — quem lê é a titular, não a máquina.
      expect(find.text('25/07/2026'), findsOneWidget);
    },
  );

  testWidgets(
    'FR-003: campo opcional vazio aparece como explicitamente vazio',
    (tester) async {
      await pumpMyProfilePage(
        tester,
        profile: buildProfile(nickname: null, phone: null, churchId: null),
      );

      // Três vezes: Apelido, Igreja de origem e telefone. Espaço em branco
      // seria ambíguo — "não informado" é uma resposta.
      expect(find.text('não informado'), findsNWidgets(3));
    },
  );

  testWidgets(
    'FR-004: a tela monta sem nenhum repositório de terceiro',
    (tester) async {
      // Sobrescreve só myProfileProvider e churchesProvider. Se a página
      // consultasse Perfil alheio, Grupo ou Ação, faltaria override e o pump
      // estouraria ao alcançar o cliente Supabase, que não existe em teste.
      await pumpMyProfilePage(tester, profile: buildProfile());

      expect(find.byType(MyProfilePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'FR-008: nome recusado pela moderação mostra a frase exata do cadastro',
    (tester) async {
      await pumpMyProfilePage(tester, profile: buildProfile(), repo: repo);

      await tester.enterText(find.byType(TextFormField).first, 'idiota');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Esse nome não pode ser usado. Tente outro.'),
          findsOneWidget);
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets(
    'FR-008: PostgrestException com nome_valido mostra a mesma frase',
    (tester) async {
      when(() => repo.updateMyProfile(any())).thenThrow(
        const PostgrestException(message: 'violates check nome_valido'),
      );
      await pumpMyProfilePage(tester, profile: buildProfile(), repo: repo);

      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Esse nome não pode ser usado. Tente outro.'),
          findsOneWidget);
    },
  );

  testWidgets(
    'FR-009: menor de idade sem Apelido não consegue salvar',
    (tester) async {
      await pumpMyProfilePage(
        tester,
        profile: buildProfile(age: 15, nickname: 'Nino'),
        repo: repo,
      );

      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNull,
          reason: 'a regra que protege o menor não afrouxa na edição');
    },
  );

  testWidgets(
    'FR-010: maior de idade pode apagar Apelido e telefone',
    (tester) async {
      await pumpMyProfilePage(tester, profile: buildProfile(), repo: repo);

      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.enterText(find.byType(TextFormField).at(2), '');
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNotNull);

      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      final sent = verify(() => repo.updateMyProfile(captureAny()))
          .captured
          .single as Profile;
      // Opcional continua opcional depois do cadastro — faz parte da promessa.
      expect(sent.toUpdateMap()['apelido'], isNull);
      expect(sent.toUpdateMap()['telefone'], isNull);
    },
  );

  testWidgets(
    'FR-011: escolher Igreja exige o consentimento destacado',
    (tester) async {
      await pumpMyProfilePage(
        tester,
        profile: buildProfile(churchId: null),
        repo: repo,
      );

      expect(find.byType(CheckboxListTile), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(testChurch.name).last);
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull,
          reason: 'a caixa nasce desmarcada e trava o salvar');

      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      expect(saveButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'FR-011: trocar de Igreja volta a exigir o consentimento',
    (tester) async {
      await pumpMyProfilePage(
        tester,
        profile: buildProfile(
          churchId: testChurch.id,
          churchConsentAt: DateTime.utc(2026, 8, 1),
        ),
        repo: repo,
      );

      expect(saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(otherChurch.name).last);
      await tester.pumpAndSettle();

      // Trocar de Igreja é um aceite novo sobre um dado sensível — o anterior
      // não vale para a nova.
      expect(saveButton(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'FR-012/SC-005: falha de rede avisa e não muda o que está na tela',
    (tester) async {
      when(() => repo.updateMyProfile(any()))
          .thenThrow(const SocketException('sem rede'));
      await pumpMyProfilePage(tester, profile: buildProfile(), repo: repo);

      await tester.enterText(find.byType(TextFormField).first, 'Ana Corrigida');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ElevatedButton));
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Não deu pra salvar agora. Verifique sua conexão e tente de novo.',
        ),
        findsOneWidget,
      );
      // A exceção foi tratada, não vazou para o framework.
      expect(tester.takeException(), isNull);
    },
  );
}

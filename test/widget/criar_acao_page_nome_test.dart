import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/presentation/create_action_page.dart';
import 'package:iasd_conecta/features/group/domain/group_category.dart';
import 'package:iasd_conecta/features/group/group_providers.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';

const _uid = 'criador-1';

final _creatorProfile = PublicProfile(
  id: _uid,
  displayName: 'José Danilo Silva do Carmo',
);

Future<void> _pump(
  WidgetTester tester, {
  required AsyncValue<PublicProfile> profile,
}) async {
  // O formulário é mais alto que os 600px do viewport padrão do teste, e o
  // botão de enviar fica fora da área clicável mesmo depois de `ensureVisible`.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(_uid),
        publicProfileProvider(_uid).overrideWith((ref) async {
          return profile.when(
            data: (p) => p,
            loading: () => throw UnimplementedError(),
            error: (e, _) => throw e,
          );
        }),
        groupCategoriesProvider.overrideWith((ref) async => <GroupCategory>[]),
      ],
      child: const MaterialApp(home: CreateActionPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _typeNameAndSubmit(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextFormField).first, name);
  final button = find.widgetWithText(ElevatedButton, 'Criar Ação');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('o campo de nome traz o texto de apoio com exemplo (FR-016)',
      (tester) async {
    await _pump(tester, profile: AsyncValue.data(_creatorProfile));

    expect(
      find.textContaining('descreve a atividade, não a pessoa'),
      findsWidgets,
    );
    expect(find.textContaining('Visita a afastado'), findsWidgets);
  });

  testWidgets('recusa o nome do próprio criador, com o motivo (FR-017, FR-018)',
      (tester) async {
    await _pump(tester, profile: AsyncValue.data(_creatorProfile));

    await _typeNameAndSubmit(tester, 'José Danilo Silva do Carmo');

    expect(
      find.textContaining('O nome da Ação descreve a atividade, não a pessoa'),
      findsOneWidget,
    );
  });

  testWidgets('recusa também sem acento e com caixa trocada (SC-006)',
      (tester) async {
    await _pump(tester, profile: AsyncValue.data(_creatorProfile));

    await _typeNameAndSubmit(tester, '  jose danilo silva do carmo ');

    expect(
      find.textContaining('O nome da Ação descreve a atividade, não a pessoa'),
      findsOneWidget,
    );
  });

  testWidgets('aceita "Visita a José" — é igualdade, não contains (FR-019)',
      (tester) async {
    await _pump(tester, profile: AsyncValue.data(_creatorProfile));

    await _typeNameAndSubmit(tester, 'Visita a José');

    expect(
      find.textContaining('O nome da Ação descreve a atividade, não a pessoa'),
      findsNothing,
    );
  });

  testWidgets(
    'com a RPC do Perfil falhando, a criação NÃO é bloqueada (research D-005)',
    (tester) async {
      // Recusar por falta de dado transformaria um problema de conexão numa
      // acusação ao Usuário.
      await _pump(
        tester,
        profile: AsyncValue.error(Exception('sem rede'), StackTrace.empty),
      );

      await _typeNameAndSubmit(tester, 'José Danilo Silva do Carmo');

      expect(
        find.textContaining('O nome da Ação descreve a atividade, não a pessoa'),
        findsNothing,
      );
    },
  );
}

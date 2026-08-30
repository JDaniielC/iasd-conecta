import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/providers.dart';
import 'package:iasd_conecta/features/action/action_providers.dart';
import 'package:iasd_conecta/features/action/data/action_repository.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/action/presentation/action_detail_page.dart';
import 'package:iasd_conecta/features/profile/domain/profile.dart';
import 'package:mocktail/mocktail.dart';

/// Change `afirmar-sem-conferir` — a desistência recusada por encerramento.
///
/// A tela esconde o botão quando a Ação já encerrou (`if (!action.isCancelled
/// && !isEnded)`), então o caminho que chega aqui é uma **corrida**: a pessoa
/// abre a tela com a Ação ainda aberta, o limite de quatro horas passa, e ela
/// toca em Desistir sobre um estado que envelheceu na mão dela.
///
/// Estreito, e é justamente por isso que precisa de teste: ninguém vai reparar
/// nele em uso normal, e o que ela vê hoje é "Não deu pra desistir agora. Tente
/// de novo." — que manda repetir uma operação que nunca mais vai funcionar,
/// sobre uma presença que continua registrada.

class MockActionRepository extends Mock implements ActionRepository {}

/// Aberta na hora em que a tela montou.
final _action = Action(
  id: 'a1',
  name: 'Acampamento',
  dateTime: DateTime(2027, 3, 10, 8),
  location: 'Sítio',
  creatorId: 'dono-1',
  createdAt: DateTime(2026, 1, 1),
);

const _me = 'quem-desiste';

Future<void> _pump(WidgetTester tester, ActionRepository repository) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  when(() => repository.fetchAction('a1')).thenAnswer((_) async => _action);
  when(() => repository.fetchAttendees('a1')).thenAnswer(
    (_) async => const [
      AttendanceWithProfile(
        profile: PublicProfile(id: _me, displayName: 'Eu'),
        status: AttendanceStatus.confirmed,
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hasProfileProvider.overrideWith((ref) async => true),
        currentUserIdProvider.overrideWithValue(_me),
        isAnonymousProvider.overrideWithValue(false),
        actionRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: ActionDetailPage(actionId: 'a1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recusa por encerramento mostra a frase do encerramento',
      (tester) async {
    final repository = MockActionRepository();
    when(() => repository.withdraw('a1')).thenThrow(
      StateError('Essa Ação já encerrou. Sua presença continua registrada.'),
    );

    await _pump(tester, repository);
    await tester.tap(find.text('Desistir'));
    await tester.pumpAndSettle();

    expect(
      find.text('Essa Ação já encerrou. Sua presença continua registrada.'),
      findsOneWidget,
    );
    // A frase genérica manda repetir algo que nunca mais vai funcionar.
    expect(find.text('Não deu pra desistir agora. Tente de novo.'), findsNothing);
  });

  testWidgets('falha que não é recusa continua com a frase genérica',
      (tester) async {
    final repository = MockActionRepository();
    when(() => repository.withdraw('a1')).thenThrow(Exception('rede caiu'));

    await _pump(tester, repository);
    await tester.tap(find.text('Desistir'));
    await tester.pumpAndSettle();

    expect(find.text('Não deu pra desistir agora. Tente de novo.'), findsOneWidget);
  });

  testWidgets('desistência que dá certo não mostra erro nenhum', (tester) async {
    final repository = MockActionRepository();
    when(() => repository.withdraw('a1')).thenAnswer((_) async {});

    await _pump(tester, repository);
    await tester.tap(find.text('Desistir'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}

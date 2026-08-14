import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/change_log/change_log_providers.dart';
import 'package:iasd_conecta/features/change_log/domain/change_log_entry.dart';
import 'package:iasd_conecta/features/change_log/presentation/change_log_section.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — a seção, em 360 px.
///
/// Os três casos que a spec trata por nome: registro vazio (que é o estado
/// normal de tudo que existia antes desta funcionalidade), registro maior que a
/// página, e autor nulo.

ChangeLogEntry _e(int i, {String? autor, ChangeLogType? tipo}) => ChangeLogEntry(
      id: 'm$i',
      type: tipo ?? ChangeLogType.memberJoined,
      createdAt: DateTime(2026, 8, 13, 10, i % 60),
      groupId: 'g1',
      authorId: autor == null ? null : 'u1',
      authorName: autor,
    );

Future<void> _pump(WidgetTester tester, List<ChangeLogEntry> entradas) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupChangeLogProvider('g1').overrideWith((ref) async => entradas),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChangeLogSection.forGroup(groupId: 'g1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('registro vazio diz que começa agora, e a tela não quebra',
      (tester) async {
    await _pump(tester, const []);
    expect(find.text('Mudanças recentes'), findsOneWidget);
    expect(find.textContaining('O registro começa agora'), findsOneWidget);
    // Nem erro, nem carregamento perpétuo.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Não deu pra carregar'), findsNothing);
  });

  testWidgets('21 registros mostram 20 e a indicação de que há mais',
      (tester) async {
    await _pump(tester, [for (var i = 0; i < 21; i++) _e(i, autor: 'P$i')]);
    expect(find.textContaining('Há mudanças mais antigas'), findsOneWidget);
    // O 21º item é só o sinalizador de "há mais" — não é exibido.
    expect(find.text('P20 entrou no Grupo'), findsNothing);
    expect(find.text('P19 entrou no Grupo'), findsOneWidget);
  });

  testWidgets('20 registros não mostram a indicação de "há mais"',
      (tester) async {
    await _pump(tester, [for (var i = 0; i < 20; i++) _e(i, autor: 'P$i')]);
    expect(find.textContaining('Há mudanças mais antigas'), findsNothing);
  });

  testWidgets('autor nulo rende frase sem sujeito, e nunca "null" na tela',
      (tester) async {
    await _pump(tester, [
      _e(1),
      _e(2, tipo: ChangeLogType.actionCancelled),
    ]);
    expect(find.text('Alguém entrou no Grupo'), findsOneWidget);
    expect(find.text('A Ação foi cancelada'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
  });
}

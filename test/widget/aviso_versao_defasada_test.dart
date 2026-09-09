import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/legal/domain/consent_status.dart';
import 'package:iasd_conecta/features/legal/legal_providers.dart';
import 'package:iasd_conecta/features/legal/presentation/widgets/accepted_version_line.dart';
import 'package:iasd_conecta/features/legal/presentation/widgets/outdated_consent_banner.dart';

/// Change `presenca-em-acao`, capability `versao-aceita-e-vigente`.
///
/// Fecha `PENDENCIAS.md` 2.29. Até aqui, `perfis.consentimento_lgpd_versao` era
/// carimbada na criação do Perfil e **nada comparava** a versão aceita com a
/// vigente — o único aviso vivia na tela de Novidades, cujo marcador de lido é
/// por instalação, então quem reinstala não era alcançado.
///
/// LGPD art. 8º, §6º: em alteração de forma ou duração do tratamento, o
/// controlador deve informar ao titular "com destaque de forma específica do
/// teor das alterações". Destaque é o aviso; teor é dizer O QUE mudou, e é por
/// isso que os testes afirmam o texto da mudança, e não só a presença do
/// cartão.

Future<void> _pump(
  WidgetTester tester,
  AsyncValue<ConsentStatus?> status, {
  Future<void> Function()? onAccept,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myConsentStatusProvider.overrideWith((ref) async {
          return status.value;
        }),
        if (onAccept != null)
          acceptCurrentLegalVersionProvider.overrideWithValue(onAccept),
      ],
      child: const MaterialApp(home: Scaffold(body: OutdatedConsentBanner())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aceite defasado mostra o que mudou, não só que mudou', (
    tester,
  ) async {
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: '1.9',
          currentVersion: '1.11',
          changesSinceAccepted: [
            '1.10 — o histórico de mudanças de Grupo e Ação ganhou prazo.',
            '1.11 — o app passou a registrar quem compareceu a uma Ação.',
          ],
        ),
      ),
    );

    expect(find.textContaining('mudou'), findsWidgets);
    // O TEOR, e não só o destaque. Um aviso que diz "os termos mudaram" e não
    // diz o quê não cumpre o art. 8º, §6º.
    expect(
      find.textContaining('registrar quem compareceu a uma Ação'),
      findsOneWidget,
    );
    expect(
      find.textContaining('histórico de mudanças de Grupo e Ação'),
      findsOneWidget,
    );
  });

  testWidgets('quem está em dia vê qual versão aceitou, sem aviso', (
    tester,
  ) async {
    // Achado C-4 da convergência 1. O aviso só aparece quando há divergência,
    // e o app não tinha onde dizer a quem está em dia sob qual texto ele está.
    // "É tudo que o app guarda sobre você" inclui isso.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myConsentStatusProvider.overrideWith((ref) async {
            return const ConsentStatus(
              acceptedVersion: '1.11',
              currentVersion: '1.11',
              changesSinceAccepted: [],
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AcceptedVersionLine()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1.11'), findsOneWidget);
  });

  testWidgets('quem tem versão desconhecida vê isso, e nenhum número', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myConsentStatusProvider.overrideWith((ref) async {
            return const ConsentStatus(
              acceptedVersion: null,
              currentVersion: '1.11',
              changesSinceAccepted: [],
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AcceptedVersionLine()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('desconhecida'), findsOneWidget);
  });

  testWidgets('aceite em dia não mostra aviso nenhum', (tester) async {
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: '1.11',
          currentVersion: '1.11',
          changesSinceAccepted: [],
        ),
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('mudou'), findsNothing);
  });

  testWidgets('versão desconhecida diz que é desconhecida e não chuta qual era',
      (tester) async {
    // São os aceites colhidos entre 2026-07-23 e 2026-08-09, quando o app só
    // gravava a data. Atribuir uma versão a eles pela data seria estimativa
    // apresentada como registro — exatamente o que a coluna existe para evitar.
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: null,
          currentVersion: '1.11',
          changesSinceAccepted: [],
        ),
      ),
    );

    expect(find.textContaining('não sabemos qual versão'), findsOneWidget);
    expect(find.textContaining('1.9'), findsNothing);
    expect(find.textContaining('1.10'), findsNothing);
  });

  testWidgets('sem Perfil não mostra aviso', (tester) async {
    await _pump(tester, const AsyncValue.data(null));

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('enquanto carrega não mostra aviso', (tester) async {
    // Um FutureProvider que ninguém leu nasce em loading, e `.value` é nulo.
    // Mostrar o aviso nesse instante piscaria "seus termos mudaram" para quem
    // está em dia — o mesmo tipo de defeito de `ProfileGuard`
    // (`PENDENCIAS.md` 2.31).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // `Completer` que nunca completa, e não `Future.delayed`: um timer
          // pendente no fim do teste reprova em `!timersPending`, e o que
          // interessa aqui é o estado de carregamento, não a passagem do tempo.
          myConsentStatusProvider.overrideWith((ref) {
            return Completer<ConsentStatus?>().future;
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: OutdatedConsentBanner())),
      ),
    );
    await tester.pump();

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('aceitar chama o caminho de reaceite', (tester) async {
    var called = 0;
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: '1.10',
          currentVersion: '1.11',
          changesSinceAccepted: ['1.11 — comparecimento.'],
        ),
      ),
      onAccept: () async => called++,
    );

    await tester.tap(find.text('Aceitar'));
    await tester.pumpAndSettle();

    expect(called, 1);
  });

  testWidgets('reaceite que falha não afirma que atualizou', (tester) async {
    // A tela não pode dizer que registrou o aceite sobre nada. O repositório
    // levanta quando zero linhas são afetadas — aqui o aviso CONTINUA na tela,
    // com o motivo, em vez de sumir como se tivesse dado certo.
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: '1.10',
          currentVersion: '1.11',
          changesSinceAccepted: ['1.11 — comparecimento.'],
        ),
      ),
      onAccept: () async => throw StateError(
        'Não deu pra registrar seu aceite agora. Verifique sua conexão e '
        'tente de novo.',
      ),
    );

    await tester.tap(find.text('Aceitar'));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsOneWidget);
    expect(
      find.textContaining('Não deu pra registrar seu aceite'),
      findsOneWidget,
    );
  });

  testWidgets('fechar sem aceitar não bloqueia e não muda o aceite', (
    tester,
  ) async {
    // Consentimento obtido sob ameaça de perder o que já se tinha não é livre.
    // A pessoa continua com tudo o que a versão aceita já cobria; o que ela não
    // recebe é o tratamento de finalidade nova.
    var called = 0;
    await _pump(
      tester,
      const AsyncValue.data(
        ConsentStatus(
          acceptedVersion: '1.10',
          currentVersion: '1.11',
          changesSinceAccepted: ['1.11 — comparecimento.'],
        ),
      ),
      onAccept: () async => called++,
    );

    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();

    expect(called, 0);
    expect(find.byType(Card), findsNothing);
  });
}

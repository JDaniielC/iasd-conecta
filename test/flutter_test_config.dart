import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Change `afirmar-sem-conferir` — **toda tela deste app é julgada na largura
/// de um celular estreito, e não na largura padrão do ambiente de teste.**
///
/// O padrão do `flutter_test` é 800x600, que é um tablet deitado. Nenhum
/// usuário deste app tem essa tela: é um app de comunidade, usado no celular.
/// Julgar layout em 800 é julgar uma tela que ninguém vê.
///
/// Estouro horizontal é a única classe de defeito aqui que o próprio framework
/// transforma em falha de teste — e só na largura certa. Cobertura não pega:
/// ela mede execução, não largura, e uma tela pode estar 100% coberta e
/// ilegível no aparelho de todo mundo.
///
/// Não é hipótese. A change `cobertura-e-tdd` julgou dez telas a 360 pela
/// primeira vez e achou **três estouros** — 229px, 72px e 39px — em telas que
/// estavam no ar, verdes no `flutter analyze` e sem uma reclamação registrada.
///
/// **Por que aqui e não em cada arquivo**: 37 telas, e 21 já fixavam a largura
/// à mão, cada uma com quatro linhas de `physicalSize`/`devicePixelRatio` mais
/// dois `addTearDown`. Espalhar a mesma verificação por 37 arquivos garante que
/// o próximo arquivo esqueça — e o arquivo que esquece é o único que não avisa.
/// Aqui vale para tudo que roda sob `test/`, inclusive o teste que ainda não
/// foi escrito.
///
/// Um teste que precise de outra largura de propósito continua podendo mexer no
/// `tester.view` dele; este arquivo só muda o ponto de partida.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final view = binding.platformDispatcher.implicitView;
  if (view != null) {
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1.0;
  }
  await testMain();
}

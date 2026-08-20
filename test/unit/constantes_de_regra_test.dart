import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/chat/domain/chat_limits.dart';
import 'package:iasd_conecta/features/legal/legal_metadata.dart';

/// `ChatLimits` e `LegalMetadata` são constantes que a regra usa, e até a
/// change `cobertura-e-tdd` nenhum teste as importava — por isso não apareciam
/// nem no lcov. Ficaram deliberadamente FORA da lista de exclusão do gate de
/// cobertura: o caminho certo era um teste importá-las.
///
/// **O que este arquivo NÃO faz**: comparar os valores com o banco. Isso é o
/// que `test/integration/limites_de_chat_test.dart` e
/// `test/integration/versao_texto_legal_registro_test.dart` já fazem, contra
/// Postgres de verdade — e é lá que precisa ficar, porque a divergência que
/// importa é entre o Dart e a migration.
///
/// O que fica aqui são as relações internas que nenhum banco confere: um
/// número sozinho pode estar certo e o CONJUNTO deles estar errado.

void main() {
  group('ChatLimits: os números precisam ser coerentes entre si', () {
    test('o teto da janela é alcançável no intervalo mínimo', () {
      // Se subir `minimumInterval` sem mexer no teto, o teto vira código morto:
      // o intervalo sozinho já impede alguém de chegar lá, e a contagem
      // regressiva na tela passa a prometer um limite que ninguém encosta.
      final fastestPossible = ChatLimits.minimumInterval * ChatLimits.windowCeiling;
      expect(
        fastestPossible,
        lessThanOrEqualTo(ChatLimits.window),
        reason: '${ChatLimits.windowCeiling} mensagens a cada '
            '${ChatLimits.minimumInterval.inSeconds}s levam '
            '${fastestPossible.inSeconds}s, mais que a janela de '
            '${ChatLimits.window.inSeconds}s',
      );
    });

    test('intervalo e janela são positivos', () {
      expect(ChatLimits.minimumInterval, greaterThan(Duration.zero));
      expect(ChatLimits.window, greaterThan(Duration.zero));
    });

    test('o teto de fixadas é pequeno de propósito — fixar não expira', () {
      // Mensagem fixada escapa do expurgo de 30 dias. Sem teto, fixar seria
      // uma forma de desligar a retenção da conversa inteira.
      expect(ChatLimits.pinnedCeiling, greaterThan(0));
      expect(ChatLimits.pinnedCeiling, lessThan(ChatLimits.windowCeiling));
    });
  });

  group('LegalMetadata: o que a titular precisa conseguir usar', () {
    test('a versão do texto legal tem forma de versão', () {
      expect(LegalMetadata.version, matches(RegExp(r'^\d+\.\d+$')));
    });

    test('a data de vigência está escrita por extenso, em português', () {
      // A data aparece na tela para a titular, não em log — "2026-08-17" ali
      // seria formato de máquina num documento que existe para ser lido.
      expect(
        LegalMetadata.effectiveDate,
        matches(RegExp(r'^\d{1,2} de \w+ de \d{4}$')),
      );
    });

    test('o canal de exercício de direitos é um e-mail utilizável', () {
      // LGPD art. 41: se este endereço estiver quebrado, o direito do titular
      // não tem por onde ser exercido.
      expect(LegalMetadata.contactEmail, contains('@'));
      expect(LegalMetadata.contactEmail.split('@').last, contains('.'));
      expect(LegalMetadata.contactEmail, isNot(contains(' ')));
    });

    test('o controlador está nomeado', () {
      expect(LegalMetadata.controllerName.trim(), isNotEmpty);
    });

    test('a região de hospedagem diz o país', () {
      // A Política afirma que o dado não sai do Brasil; a constante é de onde
      // a tela tira essa afirmação.
      expect(LegalMetadata.hostingRegion, contains('Brasil'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/coverage_summary.dart';

/// lcov sintético. Um `SF:` por arquivo, `DA:<linha>,<hits>` por linha
/// instrumentada, `end_of_record` fechando cada bloco — é o que
/// `flutter test --coverage` produz.
String _lcov(Map<String, List<int>> filesToHits) {
  final buffer = StringBuffer();
  filesToHits.forEach((path, hits) {
    buffer.writeln('SF:$path');
    for (var i = 0; i < hits.length; i++) {
      buffer.writeln('DA:${i + 1},${hits[i]}');
    }
    buffer.writeln('end_of_record');
  });
  return buffer.toString();
}

void main() {
  group('summarize: soma de linhas', () {
    test('conta linha com hit e linha sem hit', () {
      final summary = summarize(
        _lcov({
          'lib/a.dart': [1, 0, 3, 0],
        }),
      );
      expect(summary.total, 4);
      expect(summary.hit, 2);
    });

    test('soma vários arquivos', () {
      final summary = summarize(
        _lcov({
          'lib/a.dart': [1, 0],
          'lib/b.dart': [1, 1, 0],
        }),
      );
      expect(summary.total, 5);
      expect(summary.hit, 3);
    });

    test('lcov sem nenhum DA não divide por zero', () {
      final summary = summarize('SF:lib/a.dart\nend_of_record\n');
      expect(summary.total, 0);
      expect(summary.percent, 0);
    });
  });

  group('summarize: exclusão por caminho', () {
    test('lib/features/<qualquer>/data/ sai do denominador', () {
      final summary = summarize(
        _lcov({
          'lib/features/group/data/group_repository.dart': [0, 0, 0],
          'lib/features/group/presentation/group_list_page.dart': [1, 1],
        }),
      );
      expect(summary.total, 2, reason: 'só a página entra na conta');
      expect(summary.hit, 2);
    });

    test('data/ fora de features NÃO é excluído', () {
      final summary = summarize(
        _lcov({
          'lib/core/data/algo.dart': [0, 0],
        }),
      );
      expect(summary.total, 2,
          reason: 'a exclusão declarada é lib/features/*/data/, não qualquer data/');
    });

    test('lib/main.dart NÃO é excluído — nenhuma suíte o prova', () {
      // Convergência C1.3: ele já esteve na lista de exclusão, e a requirement
      // "O denominador da cobertura é declarado" recusa excluir código que
      // nenhuma outra suíte cobre. Hoje ele nem chega ao lcov, porque nenhum
      // teste o importa; se um dia chegar, conta contra o número.
      final summary = summarize(
        _lcov({
          'lib/main.dart': [0, 0, 0],
          'lib/app.dart': [1],
        }),
      );
      expect(summary.total, 4);
      expect(summary.hit, 1);
      expect(summary.excludedLines, 0);
    });

    test('chat_limits e legal_metadata NÃO são excluídos', () {
      final summary = summarize(
        _lcov({
          'lib/features/chat/domain/chat_limits.dart': [0, 0],
          'lib/features/legal/legal_metadata.dart': [0],
        }),
      );
      expect(summary.total, 3,
          reason: 'o caminho certo é um teste importá-los, não o gate ignorá-los');
      expect(summary.hit, 0);
    });

    test('o resumo diz quantas linhas foram excluídas', () {
      final summary = summarize(
        _lcov({
          'lib/features/group/data/group_repository.dart': [0, 0, 0],
          'lib/app.dart': [1],
        }),
      );
      expect(summary.excludedLines, 3);
    });
  });

  group('summarize: percentual', () {
    test('percentual é sobre o denominador já excluído', () {
      final summary = summarize(
        _lcov({
          'lib/features/group/data/group_repository.dart': [0, 0, 0, 0],
          'lib/app.dart': [1, 1, 1, 0],
        }),
      );
      // 3/4 = 75%, e não 3/8 = 37,5% que sairia sem a exclusão.
      expect(summary.percent, closeTo(75.0, 0.001));
    });
  });

  group('veredito contra o piso', () {
    test('acima do piso passa', () {
      final summary = summarize(_lcov({'lib/a.dart': [1, 1, 1, 0]}));
      expect(summary.meetsFloor(70.0), isTrue);
    });

    test('exatamente no piso passa', () {
      final summary = summarize(_lcov({'lib/a.dart': [1, 1, 1, 0]}));
      expect(summary.meetsFloor(75.0), isTrue,
          reason: 'o piso é chão, não degrau — igual ao piso não é abaixo dele');
    });

    test('abaixo do piso reprova', () {
      final summary = summarize(_lcov({'lib/a.dart': [1, 1, 1, 0]}));
      expect(summary.meetsFloor(75.1), isFalse);
    });
  });

  group('entrada malformada', () {
    test('DA sem vírgula levanta FormatException com o número da linha', () {
      expect(
        () => summarize('SF:lib/a.dart\nDA:7\nend_of_record\n'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('2'), contains('DA:7')),
        )),
      );
    });

    test('contagem de hits não numérica levanta FormatException', () {
      expect(
        () => summarize('SF:lib/a.dart\nDA:1,muitos\nend_of_record\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('DA antes de qualquer SF levanta FormatException', () {
      expect(
        () => summarize('DA:1,1\n'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('SF:'),
        )),
      );
    });

    test('linha desconhecida é ignorada, como o lcov faz', () {
      final summary = summarize(
        'TN:\nSF:lib/a.dart\nFN:3,algo\nDA:1,1\nLF:1\nLH:1\nend_of_record\n',
      );
      expect(summary.total, 1);
      expect(summary.hit, 1);
    });
  });

  group('arquivo ausente', () {
    test('readLcov de caminho inexistente levanta MissingLcovException', () {
      expect(
        () => readLcov('coverage/nao-existe-esse-arquivo.info'),
        throwsA(isA<MissingLcovException>()),
      );
    });
  });
}

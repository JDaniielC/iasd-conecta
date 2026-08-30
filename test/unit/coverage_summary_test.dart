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

  group('summarize: --no-exclusions', () {
    test('com a flag, lib/features/*/data/ entra no denominador', () {
      final summary = summarize(
        _lcov({
          'lib/features/group/data/group_repository.dart': [0, 0, 0],
          'lib/features/group/presentation/group_list_page.dart': [1, 1],
        }),
        noExclusions: true,
      );
      expect(summary.total, 5, reason: 'as 3 linhas de data/ voltam a contar');
      expect(summary.hit, 2);
      expect(summary.excludedLines, 0);
    });

    test('sem a flag, a exclusão continua valendo (regressão)', () {
      final summary = summarize(
        _lcov({'lib/features/group/data/group_repository.dart': [0, 0, 0]}),
      );
      expect(summary.total, 0);
      expect(summary.excludedLines, 3);
    });
  });

  group('normalizePath', () {
    test('caminho absoluto com /lib/ vira relativo a partir de lib/', () {
      expect(
        normalizePath('/Users/alguem/projetos/iasd/lib/app.dart'),
        'lib/app.dart',
      );
    });

    test('caminho já relativo a lib/ permanece igual', () {
      expect(normalizePath('lib/app.dart'), 'lib/app.dart');
    });

    test('caminho sem /lib/ permanece inalterado', () {
      expect(
        normalizePath('test/unit/algo_test.dart'),
        'test/unit/algo_test.dart',
      );
    });
  });

  group('summarize normaliza o caminho antes de excluir', () {
    test('exclusão de lib/features/*/data/ bate mesmo com caminho absoluto', () {
      final summary = summarize(
        'SF:/home/ci/projeto/lib/features/group/data/group_repository.dart\n'
        'DA:1,0\nDA:2,0\nend_of_record\n',
      );
      expect(summary.total, 0);
      expect(summary.excludedLines, 2);
    });
  });

  group('mergeLcov', () {
    test('arquivos diferentes nos dois relatórios aparecem os dois, sem duplicar', () {
      final merged = mergeLcov([
        _lcov({
          'lib/a.dart': [1, 0],
        }),
        _lcov({
          'lib/b.dart': [1, 1],
        }),
      ]);
      final summary = summarize(merged);
      expect(summary.total, 4);
      expect(summary.hit, 3);
    });

    test('mesma linha coberta em um relatório e não no outro conta como coberta', () {
      final merged = mergeLcov([
        _lcov({
          'lib/a.dart': [1, 0, 0], // linha 2 não coberta aqui
        }),
        _lcov({
          'lib/a.dart': [0, 1, 0], // linha 2 coberta aqui
        }),
      ]);
      final summary = summarize(merged);
      expect(summary.total, 3,
          reason: 'a linha não duplica no denominador por aparecer nos dois');
      expect(summary.hit, 2,
          reason: 'linha 1 e linha 2 cobertas por um dos dois; linha 3 em nenhum');
    });

    test(
        'mesmo arquivo por caminho absoluto num lado e relativo no outro é '
        'uma entrada só', () {
      final merged = mergeLcov([
        'SF:lib/a.dart\nDA:1,1\nDA:2,0\nend_of_record\n',
        'SF:/ci/runner/projeto/lib/a.dart\nDA:1,0\nDA:2,1\nend_of_record\n',
      ]);
      final summary = summarize(merged);
      expect(summary.total, 2,
          reason: 'sem normalizar viraria 4 — o mesmo arquivo contado duas vezes');
      expect(summary.hit, 2);
    });
  });
}

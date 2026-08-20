// Resumo de cobertura de linha a partir de coverage/lcov.info.
//
// Existe em vez de `lcov --summary` porque o binário `lcov` não está nas
// máquinas de desenvolvimento (macOS) e o formato do resumo dele diverge entre
// versões — o parse do gate quebraria entre macOS e ubuntu-latest sem ninguém
// mexer no repo. Ver openspec/changes/cobertura-e-tdd/design.md, Decisão 1.
//
// Uso:
//   dart run scripts/coverage_summary.dart --floor 72.1 [--lcov <caminho>]

import 'dart:io';

// O ÚNICO caminho de `lib/` fora do denominador, com o motivo — exclusão sem
// motivo escrito é como o número sobe sem o código melhorar: basta tirar da
// conta o que não tem teste.
//
// `lib/main.dart` já esteve nesta lista e SAIU (convergência C1.3): a
// requirement "O denominador da cobertura é declarado" recusa excluir código
// que nenhuma suíte prova, e `main.dart` não é provado por nenhuma. A exclusão
// também não mudava número nenhum — ele nem aparece no lcov, porque nenhum
// teste o importa.

/// A camada de repositório é provada por `dart test test/integration`, que roda
/// contra Postgres e não entra nesta medição. Mantê-la no denominador faria o
/// número medir a ausência da integração, não a cobertura do código.
final _repositoryLayer = RegExp(r'^lib/features/[^/]+/data/');

bool isExcluded(String path) => _repositoryLayer.hasMatch(path);

class MissingLcovException implements Exception {
  MissingLcovException(this.path);

  final String path;

  @override
  String toString() =>
      'coverage/lcov.info não existe em "$path". '
      'Rode `flutter test --coverage test/unit test/widget` antes.';
}

class CoverageSummary {
  const CoverageSummary({
    required this.hit,
    required this.total,
    required this.excludedLines,
  });

  /// Linhas instrumentadas com pelo menos uma execução, já sem as excluídas.
  final int hit;

  /// Linhas instrumentadas no denominador, já sem as excluídas.
  final int total;

  /// Linhas que ficaram fora do denominador por [isExcluded].
  final int excludedLines;

  double get percent => total == 0 ? 0 : hit * 100 / total;

  /// Igual ao piso passa: o piso é chão, não degrau.
  bool meetsFloor(double floor) => percent >= floor;

  String get formattedPercent =>
      '$hit/$total = ${percent.toStringAsFixed(1).replaceAll('.', ',')}%';
}

/// Lê e soma um lcov já em memória.
///
/// Linha `DA:` malformada levanta [FormatException] em vez de ser ignorada: um
/// parser que pula em silêncio faz o número subir quando o formato muda, e
/// ninguém descobre.
CoverageSummary summarize(String lcov) {
  var hit = 0;
  var total = 0;
  var excludedLines = 0;
  String? currentFile;

  final lines = lcov.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    final lineNumber = i + 1;

    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      continue;
    }

    if (!line.startsWith('DA:')) continue;

    if (currentFile == null) {
      throw FormatException(
        'linha $lineNumber: "$line" aparece antes de qualquer "SF:" — '
        'não há arquivo a que atribuir a linha',
      );
    }

    final payload = line.substring(3);
    final comma = payload.indexOf(',');
    if (comma < 0) {
      throw FormatException(
        'linha $lineNumber: "$line" não tem vírgula separando '
        'número da linha e contagem de execuções',
      );
    }

    final hits = int.tryParse(payload.substring(comma + 1).trim());
    if (hits == null) {
      throw FormatException(
        'linha $lineNumber: "$line" tem contagem de execuções não numérica',
      );
    }

    if (isExcluded(currentFile)) {
      excludedLines++;
      continue;
    }

    total++;
    if (hits > 0) hit++;
  }

  return CoverageSummary(
    hit: hit,
    total: total,
    excludedLines: excludedLines,
  );
}

String readLcov(String path) {
  final file = File(path);
  if (!file.existsSync()) throw MissingLcovException(path);
  return file.readAsStringSync();
}

void main(List<String> args) {
  var lcovPath = 'coverage/lcov.info';
  double? floor;

  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--lcov') lcovPath = args[i + 1];
    if (args[i] == '--floor') floor = double.tryParse(args[i + 1]);
  }

  if (floor == null) {
    stderr.writeln('erro: --floor <número> é obrigatório.');
    exit(2);
  }

  final CoverageSummary summary;
  try {
    summary = summarize(readLcov(lcovPath));
  } on MissingLcovException catch (e) {
    stderr.writeln('erro: $e');
    exit(2);
  } on FormatException catch (e) {
    stderr.writeln('erro: $lcovPath está malformado — ${e.message}');
    exit(2);
  }

  final floorLabel = floor.toStringAsFixed(1).replaceAll('.', ',');
  stdout.writeln('cobertura: ${summary.formattedPercent}   piso: $floorLabel%');
  stdout.writeln(
    '${summary.excludedLines} linhas fora do denominador '
    '(lib/features/*/data/ — ver o comentário no topo deste script)',
  );

  if (!summary.meetsFloor(floor)) {
    stderr.writeln(
      'REPROVADO: cobertura abaixo do piso. '
      'O conserto é escrever o teste que falta — baixar o piso exige motivo '
      'no corpo do commit.',
    );
    exit(1);
  }

  stdout.writeln('ok: cobertura no piso ou acima.');
}

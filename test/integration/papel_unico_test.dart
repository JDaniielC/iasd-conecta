import 'dart:io';

import 'package:test/test.dart';

/// Change `suite-determinista-2` — "cada papel de teste tem uma definição
/// só" deixa de ser dívida tolerada e vira regra verificável.
///
/// Falha quando algum arquivo, fora de `acao_restrita_helper.dart`, DEFINE
/// uma função `asUser`, `asVisitor` ou `asAnon` que REIMPLEMENTA a troca de
/// papel (contém o SQL bruto `set role authenticated`), em vez de delegar
/// para a definição compartilhada.
///
/// Uma delegação de uma linha — `asUser` que só chama `shared.asUser(conn,
/// uid, action)` — como `visibilidade_liderancas_test.dart` e
/// `votos_visibilidade_test.dart` já faziam antes desta change, para fixar
/// um uid do próprio arquivo — NÃO é a cópia que esta verificação combate:
/// ela não duplica lógica, só nomeia uma aplicação parcial. O que ela pega é
/// o SQL reescrito de novo, que foi exatamente o achado desta change em 48
/// arquivos.
final _definicaoDePapel = RegExp(
  r'(?:Future<[^>]*>)\s+_?as(?:User|Visitor|Anon)\s*(?:<[^>]*>)?\s*\(',
);

const _arquivoCanonico = 'acao_restrita_helper.dart';
const _janelaDeReimplementacao = 300;

void main() {
  test(
    'nenhum arquivo além de acao_restrita_helper.dart reimplementa asUser/asVisitor/asAnon',
    () {
      final dir = Directory('test/integration');
      final ofensores = <String>[];

      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith(_arquivoCanonico)) continue;
        if (entity.path.endsWith('papel_unico_test.dart')) continue;
        final content = entity.readAsStringSync();
        for (final match in _definicaoDePapel.allMatches(content)) {
          final janela = content.substring(
            match.end,
            (match.end + _janelaDeReimplementacao).clamp(0, content.length),
          );
          if (janela.contains("'set role authenticated'")) {
            ofensores.add(entity.path);
            break;
          }
        }
      }

      expect(
        ofensores,
        isEmpty,
        reason: 'definição local que REIMPLEMENTA asUser/asVisitor/asAnon '
            '(em vez de delegar) fora de $_arquivoCanonico em: '
            '${ofensores.join(', ')}',
      );
    },
  );
}

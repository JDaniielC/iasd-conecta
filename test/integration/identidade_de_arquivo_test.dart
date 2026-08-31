import 'dart:io';

import 'package:test/test.dart';

/// Change `suite-determinista-2` — a suíte é determinística em paralelo
/// porque cada arquivo tem identidade própria. Este teste é a verificação que
/// impede a volta: sem ela, o conserto da seção 1 dura até a próxima change
/// escrever um uid que já tem dono.
///
/// Varre `test/integration/*.dart` procurando identificadores no formato de
/// UUID e falha quando um aparece em mais de um arquivo — dizendo quais dois
/// e qual identificador, porque uma falha que só diz "há colisão" custa a
/// mesma investigação que ela deveria evitar.
///
/// `00000000-0000-0000-0000-000000000000` é a única exceção, e é declarada:
/// não é identidade de teste, é o `instance_id` boilerplate de `auth.users`
/// que todo helper de criação de usuário fake usa — compartilhado por
/// desenho, não colisão.
final _uuidPattern = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);

const _sharedByDesign = '00000000-0000-0000-0000-000000000000';

void main() {
  test('nenhum uid de teste aparece em mais de um arquivo de test/integration',
      () {
    final dir = Directory('test/integration');
    final filesByUid = <String, Set<String>>{};

    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      final uidsInFile = _uuidPattern
          .allMatches(content)
          .map((m) => m.group(0)!.toLowerCase())
          .toSet();
      for (final uid in uidsInFile) {
        if (uid == _sharedByDesign) continue;
        filesByUid.putIfAbsent(uid, () => {}).add(entity.path);
      }
    }

    final collisions = {
      for (final entry in filesByUid.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };

    expect(
      collisions,
      isEmpty,
      reason: collisions.entries
          .map((e) => '${e.key} aparece em: ${e.value.join(', ')}')
          .join('\n'),
    );
  });
}

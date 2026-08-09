import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';

void main() {
  group('NovoGrupo.prontoParaEnviar', () {
    test('falso sem nome', () {
      const group = NewGroup(name: '  ', category: 'Jovem');
      expect(group.isReadyToSubmit, isFalse);
    });

    test('falso sem categoria', () {
      const group = NewGroup(name: 'Grupo', category: '');
      expect(group.isReadyToSubmit, isFalse);
    });

    test('verdadeiro com nome e categoria preenchidos, sem horário/local', () {
      const group = NewGroup(name: 'Grupo', category: 'Jovem');
      expect(group.isReadyToSubmit, isTrue);
    });

    test('detalhes opcional não afeta prontoParaEnviar', () {
      const group = NewGroup(
        name: 'Grupo',
        category: 'Jovem',
        details: null,
      );
      expect(group.isReadyToSubmit, isTrue);
    });
  });

  group('NovoGrupo.toInsertMap', () {
    test('normaliza detalhes em branco pra null e inclui dono/igreja', () {
      const group = NewGroup(
        name: ' Grupo ',
        category: 'Jovem',
        details: '   ',
      );
      final map = group.toInsertMap(ownerId: 'abc', churchId: 'igreja-1');
      expect(map['nome'], 'Grupo');
      expect(map['horario'], isNull);
      expect(map['local'], isNull);
      expect(map['detalhes'], isNull);
      expect(map['dono_id'], 'abc');
      expect(map['igreja_id'], 'igreja-1');
    });
  });

  group('Grupo.souDono', () {
    final group = Group(
      id: 'g1',
      name: 'Grupo',
      category: 'Jovem',
      ownerId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    );

    test('verdadeiro quando o id bate com dono_id', () {
      expect(group.isOwner('dono-1'), isTrue);
    });

    test('falso pra outro usuário', () {
      expect(group.isOwner('outro'), isFalse);
    });

    test('falso quando não há usuário atual', () {
      expect(group.isOwner(null), isFalse);
    });
  });
}

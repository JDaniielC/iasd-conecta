import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/grupo/domain/grupo.dart';

void main() {
  group('NovoGrupo.prontoParaEnviar', () {
    test('falso sem nome', () {
      const grupo = NovoGrupo(nome: '  ', categoria: 'Jovem');
      expect(grupo.prontoParaEnviar, isFalse);
    });

    test('falso sem categoria', () {
      const grupo = NovoGrupo(nome: 'Grupo', categoria: '');
      expect(grupo.prontoParaEnviar, isFalse);
    });

    test('verdadeiro com nome e categoria preenchidos, sem horário/local', () {
      const grupo = NovoGrupo(nome: 'Grupo', categoria: 'Jovem');
      expect(grupo.prontoParaEnviar, isTrue);
    });

    test('detalhes opcional não afeta prontoParaEnviar', () {
      const grupo = NovoGrupo(
        nome: 'Grupo',
        categoria: 'Jovem',
        detalhes: null,
      );
      expect(grupo.prontoParaEnviar, isTrue);
    });
  });

  group('NovoGrupo.toInsertMap', () {
    test('normaliza detalhes em branco pra null e inclui dono/igreja', () {
      const grupo = NovoGrupo(
        nome: ' Grupo ',
        categoria: 'Jovem',
        detalhes: '   ',
      );
      final map = grupo.toInsertMap(donoId: 'abc', igrejaId: 'igreja-1');
      expect(map['nome'], 'Grupo');
      expect(map['horario'], isNull);
      expect(map['local'], isNull);
      expect(map['detalhes'], isNull);
      expect(map['dono_id'], 'abc');
      expect(map['igreja_id'], 'igreja-1');
    });
  });

  group('Grupo.souDono', () {
    final grupo = Grupo(
      id: 'g1',
      nome: 'Grupo',
      categoria: 'Jovem',
      donoId: 'dono-1',
      createdAt: DateTime(2026, 1, 1),
    );

    test('verdadeiro quando o id bate com dono_id', () {
      expect(grupo.souDono('dono-1'), isTrue);
    });

    test('falso pra outro usuário', () {
      expect(grupo.souDono('outro'), isFalse);
    });

    test('falso quando não há usuário atual', () {
      expect(grupo.souDono(null), isFalse);
    });
  });
}

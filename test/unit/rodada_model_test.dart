import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/acao/domain/rodada.dart';

void main() {
  group('NovaRodada.prontoParaEnviar', () {
    test('falso com prazo no passado', () {
      final rodada = NovaRodada(prazo: DateTime.now().subtract(const Duration(days: 1)));
      expect(rodada.prontoParaEnviar, isFalse);
    });

    test('verdadeiro com prazo no futuro', () {
      final rodada = NovaRodada(prazo: DateTime.now().add(const Duration(days: 1)));
      expect(rodada.prontoParaEnviar, isTrue);
    });
  });

  group('NovaRodada.toInsertMap', () {
    test('inclui grupo_id e aberta_por', () {
      final rodada = NovaRodada(prazo: DateTime.now().add(const Duration(days: 1)));
      final map = rodada.toInsertMap(grupoId: 'g1', abertaPor: 'u1');
      expect(map['grupo_id'], 'g1');
      expect(map['aberta_por'], 'u1');
      expect(map['prazo'], isNotNull);
    });
  });

  group('Rodada.aberta', () {
    test('verdadeiro quando fechadaEm é nulo', () {
      final rodada = Rodada(
        id: 'r1',
        grupoId: 'g1',
        abertaPor: 'u1',
        prazo: DateTime.now().add(const Duration(days: 1)),
      );
      expect(rodada.aberta, isTrue);
    });

    test('falso quando fechadaEm está preenchido', () {
      final rodada = Rodada(
        id: 'r1',
        grupoId: 'g1',
        abertaPor: 'u1',
        prazo: DateTime.now(),
        fechadaEm: DateTime.now(),
      );
      expect(rodada.aberta, isFalse);
    });
  });
}

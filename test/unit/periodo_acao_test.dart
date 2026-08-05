import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/acao/domain/acao.dart';

void main() {
  group('acaoNoSabado', () {
    test('sexta antes das 17:30 não é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 24, 17, 29)), isFalse);
    });

    test('sexta às 17:30 já é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 24, 17, 30)), isTrue);
    });

    test('sexta à noite é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 24, 22, 0)), isTrue);
    });

    test('sábado de madrugada ainda é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 25, 6, 0)), isTrue);
    });

    test('sábado antes das 17:30 é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 25, 17, 29)), isTrue);
    });

    test('sábado a partir das 17:30 não é mais Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 25, 17, 30)), isFalse);
    });

    test('domingo não é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 26, 12, 0)), isFalse);
    });

    test('quarta-feira não é Sábado', () {
      expect(acaoNoSabado(DateTime(2026, 7, 22, 12, 0)), isFalse);
    });
  });

  group('periodoDaAcao', () {
    final agora = DateTime(2026, 7, 22, 10, 0); // quarta-feira

    test('Sábado tem prioridade mesmo caindo dentro de "essa semana"', () {
      final sabado = DateTime(2026, 7, 25, 10, 0);
      expect(periodoDaAcao(sabado, agora), PeriodoAcao.sabado);
    });

    test('mesmo dia de agora, fora da janela de Sábado, é Hoje', () {
      expect(periodoDaAcao(DateTime(2026, 7, 22, 20, 0), agora), PeriodoAcao.hoje);
    });

    test('dentro da semana corrente (domingo-sábado), mas não hoje, é Essa semana', () {
      expect(periodoDaAcao(DateTime(2026, 7, 23, 9, 0), agora), PeriodoAcao.essaSemana);
    });

    test('fora da semana corrente é Outras datas', () {
      expect(periodoDaAcao(DateTime(2026, 8, 5, 9, 0), agora), PeriodoAcao.outras);
    });

    test('no passado, fora da semana corrente, também é Outras datas', () {
      expect(periodoDaAcao(DateTime(2026, 6, 1, 9, 0), agora), PeriodoAcao.outras);
    });
  });
}

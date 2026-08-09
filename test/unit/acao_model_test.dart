import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  final dataFutura = DateTime.now().add(const Duration(days: 7));

  group('NovaAcao.prontoParaEnviar', () {
    test('falso sem nome', () {
      final acao = NovaAcao(nome: '  ', dataHora: dataFutura, local: 'Sede');
      expect(acao.prontoParaEnviar, isFalse);
    });

    test('falso sem local', () {
      final acao = NovaAcao(nome: 'Retiro', dataHora: dataFutura, local: '');
      expect(acao.prontoParaEnviar, isFalse);
    });

    test('falso com limite de vagas zero', () {
      final acao = NovaAcao(
        nome: 'Retiro',
        dataHora: dataFutura,
        local: 'Sede',
        limiteVagas: 0,
      );
      expect(acao.prontoParaEnviar, isFalse);
    });

    test('verdadeiro com campos obrigatórios preenchidos, sem limite', () {
      final acao = NovaAcao(nome: 'Retiro', dataHora: dataFutura, local: 'Sede');
      expect(acao.prontoParaEnviar, isTrue);
    });

    test('verdadeiro com limite de vagas positivo', () {
      final acao = NovaAcao(
        nome: 'Retiro',
        dataHora: dataFutura,
        local: 'Sede',
        limiteVagas: 20,
      );
      expect(acao.prontoParaEnviar, isTrue);
    });
  });

  group('NovaAcao.toInsertMap', () {
    test('normaliza detalhes em branco pra null e inclui criador', () {
      final acao = NovaAcao(
        nome: ' Retiro ',
        dataHora: dataFutura,
        local: 'Sede',
        detalhes: '   ',
      );
      final map = acao.toInsertMap(criadorId: 'abc');
      expect(map['nome'], 'Retiro');
      expect(map['detalhes'], isNull);
      expect(map['criador_id'], 'abc');
      expect(map['limite_vagas'], isNull);
    });
  });

  group('Acao.souCriador', () {
    final acao = Acao(
      id: 'a1',
      nome: 'Retiro',
      dataHora: dataFutura,
      local: 'Sede',
      criadorId: 'criador-1',
      createdAt: dataFutura,
    );

    test('verdadeiro quando o id bate com criador_id', () {
      expect(acao.souCriador('criador-1'), isTrue);
    });

    test('falso pra outro usuário', () {
      expect(acao.souCriador('outro'), isFalse);
    });

    test('falso sem usuário atual', () {
      expect(acao.souCriador(null), isFalse);
    });
  });

  group('Acao.cancelada', () {
    test('falso quando canceladaEm é nulo', () {
      final acao = Acao(
        id: 'a1',
        nome: 'Retiro',
        dataHora: dataFutura,
        local: 'Sede',
        criadorId: 'c1',
        createdAt: dataFutura,
      );
      expect(acao.cancelada, isFalse);
    });

    test('verdadeiro quando canceladaEm está preenchido', () {
      final acao = Acao(
        id: 'a1',
        nome: 'Retiro',
        dataHora: dataFutura,
        local: 'Sede',
        criadorId: 'c1',
        createdAt: dataFutura,
        canceladaEm: DateTime.now(),
      );
      expect(acao.cancelada, isTrue);
    });
  });
}

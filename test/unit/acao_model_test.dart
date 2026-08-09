import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  final dataFutura = DateTime.now().add(const Duration(days: 7));

  group('NovaAcao.prontoParaEnviar', () {
    test('falso sem nome', () {
      final acao = NewAction(name: '  ', dateTime: dataFutura, local: 'Sede');
      expect(acao.isReadyToSubmit, isFalse);
    });

    test('falso sem local', () {
      final acao = NewAction(name: 'Retiro', dateTime: dataFutura, local: '');
      expect(acao.isReadyToSubmit, isFalse);
    });

    test('falso com limite de vagas zero', () {
      final acao = NewAction(
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        capacity: 0,
      );
      expect(acao.isReadyToSubmit, isFalse);
    });

    test('verdadeiro com campos obrigatórios preenchidos, sem limite', () {
      final acao = NewAction(name: 'Retiro', dateTime: dataFutura, local: 'Sede');
      expect(acao.isReadyToSubmit, isTrue);
    });

    test('verdadeiro com limite de vagas positivo', () {
      final acao = NewAction(
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        capacity: 20,
      );
      expect(acao.isReadyToSubmit, isTrue);
    });
  });

  group('NovaAcao.toInsertMap', () {
    test('normaliza detalhes em branco pra null e inclui criador', () {
      final acao = NewAction(
        name: ' Retiro ',
        dateTime: dataFutura,
        local: 'Sede',
        details: '   ',
      );
      final map = acao.toInsertMap(creatorId: 'abc');
      expect(map['nome'], 'Retiro');
      expect(map['detalhes'], isNull);
      expect(map['criador_id'], 'abc');
      expect(map['limite_vagas'], isNull);
    });
  });

  group('Acao.souCriador', () {
    final acao = Action(
      id: 'a1',
      name: 'Retiro',
      dateTime: dataFutura,
      local: 'Sede',
      creatorId: 'criador-1',
      createdAt: dataFutura,
    );

    test('verdadeiro quando o id bate com criador_id', () {
      expect(acao.isCreator('criador-1'), isTrue);
    });

    test('falso pra outro usuário', () {
      expect(acao.isCreator('outro'), isFalse);
    });

    test('falso sem usuário atual', () {
      expect(acao.isCreator(null), isFalse);
    });
  });

  group('Acao.cancelada', () {
    test('falso quando canceladaEm é nulo', () {
      final acao = Action(
        id: 'a1',
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        creatorId: 'c1',
        createdAt: dataFutura,
      );
      expect(acao.isCancelled, isFalse);
    });

    test('verdadeiro quando canceladaEm está preenchido', () {
      final acao = Action(
        id: 'a1',
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        creatorId: 'c1',
        createdAt: dataFutura,
        cancelledAt: DateTime.now(),
      );
      expect(acao.isCancelled, isTrue);
    });
  });
}

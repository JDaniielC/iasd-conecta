import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  final dataFutura = DateTime.now().add(const Duration(days: 7));

  group('NovaAcao.prontoParaEnviar', () {
    test('falso sem nome', () {
      final action = NewAction(name: '  ', dateTime: dataFutura, local: 'Sede');
      expect(action.isReadyToSubmit, isFalse);
    });

    test('falso sem local', () {
      final action = NewAction(name: 'Retiro', dateTime: dataFutura, local: '');
      expect(action.isReadyToSubmit, isFalse);
    });

    test('falso com limite de vagas zero', () {
      final action = NewAction(
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        capacity: 0,
      );
      expect(action.isReadyToSubmit, isFalse);
    });

    test('verdadeiro com campos obrigatórios preenchidos, sem limite', () {
      final action = NewAction(name: 'Retiro', dateTime: dataFutura, local: 'Sede');
      expect(action.isReadyToSubmit, isTrue);
    });

    test('verdadeiro com limite de vagas positivo', () {
      final action = NewAction(
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        capacity: 20,
      );
      expect(action.isReadyToSubmit, isTrue);
    });
  });

  group('NovaAcao.toInsertMap', () {
    test('normaliza detalhes em branco pra null e inclui criador', () {
      final action = NewAction(
        name: ' Retiro ',
        dateTime: dataFutura,
        local: 'Sede',
        details: '   ',
      );
      final map = action.toInsertMap(creatorId: 'abc');
      expect(map['nome'], 'Retiro');
      expect(map['detalhes'], isNull);
      expect(map['criador_id'], 'abc');
      expect(map['limite_vagas'], isNull);
    });
  });

  group('Acao.souCriador', () {
    final action = Action(
      id: 'a1',
      name: 'Retiro',
      dateTime: dataFutura,
      local: 'Sede',
      creatorId: 'criador-1',
      createdAt: dataFutura,
    );

    test('verdadeiro quando o id bate com criador_id', () {
      expect(action.isCreator('criador-1'), isTrue);
    });

    test('falso pra outro usuário', () {
      expect(action.isCreator('outro'), isFalse);
    });

    test('falso sem usuário atual', () {
      expect(action.isCreator(null), isFalse);
    });
  });

  group('Acao.cancelada', () {
    test('falso quando canceladaEm é nulo', () {
      final action = Action(
        id: 'a1',
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        creatorId: 'c1',
        createdAt: dataFutura,
      );
      expect(action.isCancelled, isFalse);
    });

    test('verdadeiro quando canceladaEm está preenchido', () {
      final action = Action(
        id: 'a1',
        name: 'Retiro',
        dateTime: dataFutura,
        local: 'Sede',
        creatorId: 'c1',
        createdAt: dataFutura,
        cancelledAt: DateTime.now(),
      );
      expect(action.isCancelled, isTrue);
    });
  });
}

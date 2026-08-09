import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';

void main() {
  group('NovaRodada.prontoParaEnviar', () {
    test('falso com prazo no passado', () {
      final rodada = NewVotingRound(deadline: DateTime.now().subtract(const Duration(days: 1)));
      expect(rodada.isReadyToSubmit, isFalse);
    });

    test('verdadeiro com prazo no futuro', () {
      final rodada = NewVotingRound(deadline: DateTime.now().add(const Duration(days: 1)));
      expect(rodada.isReadyToSubmit, isTrue);
    });
  });

  group('NovaRodada.toInsertMap', () {
    test('inclui grupo_id e aberta_por', () {
      final rodada = NewVotingRound(deadline: DateTime.now().add(const Duration(days: 1)));
      final map = rodada.toInsertMap(grupoId: 'g1', abertaPor: 'u1');
      expect(map['grupo_id'], 'g1');
      expect(map['aberta_por'], 'u1');
      expect(map['prazo'], isNotNull);
    });
  });

  group('Rodada.aberta', () {
    test('verdadeiro quando fechadaEm é nulo', () {
      final rodada = VotingRound(
        id: 'r1',
        grupoId: 'g1',
        abertaPor: 'u1',
        deadline: DateTime.now().add(const Duration(days: 1)),
      );
      expect(rodada.aberta, isTrue);
    });

    test('falso quando fechadaEm está preenchido', () {
      final rodada = VotingRound(
        id: 'r1',
        grupoId: 'g1',
        abertaPor: 'u1',
        deadline: DateTime.now(),
        fechadaEm: DateTime.now(),
      );
      expect(rodada.aberta, isFalse);
    });
  });
}

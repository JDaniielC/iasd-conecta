import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';

void main() {
  group('NovaRodada.prontoParaEnviar', () {
    test('falso com prazo no passado', () {
      final votingRound = NewVotingRound(deadline: DateTime.now().subtract(const Duration(days: 1)));
      expect(votingRound.isReadyToSubmit, isFalse);
    });

    test('verdadeiro com prazo no futuro', () {
      final votingRound = NewVotingRound(deadline: DateTime.now().add(const Duration(days: 1)));
      expect(votingRound.isReadyToSubmit, isTrue);
    });
  });

  group('NovaRodada.toInsertMap', () {
    test('inclui grupo_id e aberta_por', () {
      final votingRound = NewVotingRound(deadline: DateTime.now().add(const Duration(days: 1)));
      final map = votingRound.toInsertMap(groupId: 'g1', openedBy: 'u1');
      expect(map['grupo_id'], 'g1');
      expect(map['aberta_por'], 'u1');
      expect(map['prazo'], isNotNull);
    });
  });

  group('Rodada.aberta', () {
    test('verdadeiro quando fechadaEm é nulo', () {
      final votingRound = VotingRound(
        id: 'r1',
        groupId: 'g1',
        openedBy: 'u1',
        deadline: DateTime.now().add(const Duration(days: 1)),
      );
      expect(votingRound.isOpen, isTrue);
    });

    test('falso quando fechadaEm está preenchido', () {
      final votingRound = VotingRound(
        id: 'r1',
        groupId: 'g1',
        openedBy: 'u1',
        deadline: DateTime.now(),
        closedAt: DateTime.now(),
      );
      expect(votingRound.isOpen, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/voting_round.dart';
import 'package:iasd_conecta/features/leadership/domain/leadership_declaration.dart';

/// Os modelos das duas features cobertas na frente de telas da change
/// `cobertura-e-tdd`: `VotingRound` estava em 7/20 e `LeadershipDeclaration`
/// em 6/18. As telas passaram a ser testadas; os modelos que elas leem, não.

void main() {
  group('VotingRound: aberta é a ausência de fechamento', () {
    test('sem fechada_em, a Rodada está aberta', () {
      final round = VotingRound.fromMap({
        'id': 'r1',
        'grupo_id': 'g1',
        'aberta_por': 'dona',
        'prazo': '2027-03-10T22:30:00Z',
        'fechada_em': null,
        'vencedora_id': null,
      });

      expect(round.isOpen, isTrue);
      expect(round.closedAt, isNull);
      expect(round.winnerId, isNull);
    });

    test('com fechada_em, está fechada — mesmo que o prazo ainda não tenha vindo',
        () {
      // Encerrar antes do prazo é o `force: true` do Dono do Grupo. O estado
      // vem do carimbo, nunca de comparar o prazo com o relógio.
      final round = VotingRound.fromMap({
        'id': 'r1',
        'grupo_id': 'g1',
        'aberta_por': 'dona',
        'prazo': '2099-01-01T00:00:00Z',
        'fechada_em': '2026-08-20T10:00:00Z',
        'vencedora_id': 'c1',
      });

      expect(round.isOpen, isFalse);
      expect(round.winnerId, 'c1');
    });
  });

  group('NewVotingRound: prazo no passado não está pronto para enviar', () {
    test('prazo no futuro está pronto', () {
      final round = NewVotingRound(
        deadline: DateTime.now().add(const Duration(days: 1)),
      );
      expect(round.isReadyToSubmit, isTrue);
    });

    test('prazo no passado não está', () {
      final round = NewVotingRound(
        deadline: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(round.isReadyToSubmit, isFalse);
    });

    test('toInsertMap manda o prazo em UTC, e nunca o grupo do cliente sozinho',
        () {
      final round = NewVotingRound(deadline: DateTime.utc(2027, 3, 10, 22, 30));
      final map = round.toInsertMap(groupId: 'g1', openedBy: 'dona');

      expect(map['grupo_id'], 'g1');
      expect(map['aberta_por'], 'dona');
      expect(map['prazo'], '2027-03-10T22:30:00.000Z');
    });
  });

  group('Vote', () {
    test('lê usuario_id e candidata_id', () {
      final vote = Vote.fromMap({'usuario_id': 'u1', 'candidata_id': 'c1'});
      expect(vote.userId, 'u1');
      expect(vote.candidateId, 'c1');
    });
  });

  group('LeadershipDeclaration: status vem dos dois carimbos, nunca de coluna', () {
    LeadershipDeclaration parse({String? confirmedAt, String? rejectedAt}) =>
        LeadershipDeclaration.fromMap({
          'id': 'd1',
          'grupo_id': 'g1',
          'usuario_id': 'u1',
          'ano': 2026,
          'declarado_em': '2026-02-01T00:00:00Z',
          'confirmado_por': confirmedAt == null ? null : 'admin-1',
          'confirmado_em': confirmedAt,
          'rejeitado_em': rejectedAt,
        });

    test('sem carimbo nenhum, está pendente', () {
      expect(parse().status, LeadershipStatus.pending);
    });

    test('com confirmado_em, está confirmada', () {
      final declaration = parse(confirmedAt: '2026-03-01T00:00:00Z');
      expect(declaration.status, LeadershipStatus.confirmed);
      expect(declaration.confirmedBy, 'admin-1');
    });

    test('com rejeitado_em, está rejeitada', () {
      expect(
        parse(rejectedAt: '2026-03-01T00:00:00Z').status,
        LeadershipStatus.rejected,
      );
    });

    test('confirmada vence rejeitada quando os dois carimbos existem', () {
      // Autodeclarar de novo depois de rejeitada reabre a análise, e a
      // confirmação posterior é a que vale.
      final declaration = parse(
        confirmedAt: '2026-04-01T00:00:00Z',
        rejectedAt: '2026-03-01T00:00:00Z',
      );
      expect(declaration.status, LeadershipStatus.confirmed);
    });
  });

  group('LeadershipDeclaration.isCurrentFor (FR-008)', () {
    LeadershipDeclaration declaration({
      required int year,
      DateTime? confirmedAt,
      DateTime? rejectedAt,
    }) =>
        LeadershipDeclaration(
          id: 'd1',
          groupId: 'g1',
          userId: 'u1',
          year: year,
          declaredAt: DateTime(year, 2, 1),
          confirmedAt: confirmedAt,
          rejectedAt: rejectedAt,
        );

    test('confirmada no ano perguntado é atual', () {
      final d = declaration(year: 2026, confirmedAt: DateTime(2026, 3, 1));
      expect(d.isCurrentFor(2026), isTrue);
    });

    test('confirmada em ano anterior NÃO é atual — sem job, a comparação é aqui',
        () {
      final d = declaration(year: 2025, confirmedAt: DateTime(2025, 3, 1));
      expect(d.isCurrentFor(2026), isFalse);
    });

    test('pendente no ano certo não é atual — falta a confirmação', () {
      expect(declaration(year: 2026).isCurrentFor(2026), isFalse);
    });

    test('rejeitada no ano certo não é atual', () {
      final d = declaration(year: 2026, rejectedAt: DateTime(2026, 3, 1));
      expect(d.isCurrentFor(2026), isFalse);
    });
  });
}

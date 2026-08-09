import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  final dataFutura = DateTime.now().add(const Duration(days: 7));

  group('NovaAcao.prontoParaEnviar (Dupla Missionária)', () {
    test('falso quando isMissionaryPair mas sem visitedGender', () {
      final acao = NovaAcao(
        nome: 'Visita',
        dataHora: dataFutura,
        local: 'Casa',
        isMissionaryPair: true,
      );
      expect(acao.prontoParaEnviar, isFalse);
    });

    test('verdadeiro quando isMissionaryPair com visitedGender preenchido', () {
      final acao = NovaAcao(
        nome: 'Visita',
        dataHora: dataFutura,
        local: 'Casa',
        isMissionaryPair: true,
        visitedGender: VisitedGender.male,
      );
      expect(acao.prontoParaEnviar, isTrue);
    });
  });

  group('NovaAcao.toInsertMap (Dupla Missionária)', () {
    test('FR-003: força limite_vagas=2 quando isMissionaryPair, ignorando limiteVagas informado', () {
      final acao = NovaAcao(
        nome: 'Visita',
        dataHora: dataFutura,
        local: 'Casa',
        limiteVagas: 50,
        isMissionaryPair: true,
        visitedGender: VisitedGender.female,
      );
      final map = acao.toInsertMap(criadorId: 'c1');
      expect(map['limite_vagas'], 2);
      expect(map['eh_dupla_missionaria'], isTrue);
      expect(map['genero_visitado'], 'feminino');
    });

    test('não marca eh_dupla_missionaria quando isMissionaryPair é falso (default)', () {
      final acao = NovaAcao(nome: 'Retiro', dataHora: dataFutura, local: 'Sede', limiteVagas: 10);
      final map = acao.toInsertMap(criadorId: 'c1');
      expect(map['limite_vagas'], 10);
      expect(map['eh_dupla_missionaria'], isFalse);
      expect(map['genero_visitado'], isNull);
    });
  });

  group('Acao.fromMap (Dupla Missionária)', () {
    test('lê isMissionaryPair e visitedGender do map', () {
      final acao = Acao.fromMap({
        'id': 'a1',
        'nome': 'Visita',
        'data_hora': dataFutura.toIso8601String(),
        'local': 'Casa',
        'criador_id': 'c1',
        'created_at': dataFutura.toIso8601String(),
        'limite_vagas': 2,
        'eh_dupla_missionaria': true,
        'genero_visitado': 'masculino',
      });
      expect(acao.isMissionaryPair, isTrue);
      expect(acao.visitedGender, VisitedGender.male);
    });

    test('visitedGender nulo quando genero_visitado é nulo', () {
      final acao = Acao.fromMap({
        'id': 'a1',
        'nome': 'Retiro',
        'data_hora': dataFutura.toIso8601String(),
        'local': 'Sede',
        'criador_id': 'c1',
        'created_at': dataFutura.toIso8601String(),
      });
      expect(acao.isMissionaryPair, isFalse);
      expect(acao.visitedGender, isNull);
    });
  });
}

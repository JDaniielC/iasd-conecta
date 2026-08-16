import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

/// Change `acao-direcionada-a-grupo` — o modelo não forma a combinação que o
/// banco recusa.
///
/// `acoes_restrita_exige_grupo` recusa restrição sem Grupo. Aqui a garantia é
/// mais simples e vem antes: numa Ação avulsa a chave `restrita_ao_grupo`
/// sequer é enviada, então não há como o formulário montar o `insert` que o
/// banco rejeitaria.

void main() {
  group('NewAction.toInsertMap', () {
    test('Ação avulsa não envia restrita_ao_grupo', () {
      final map = NewAction(
        name: 'Culto',
        dateTime: DateTime(2027, 1, 1),
        location: 'Sede',
      ).toInsertMap(creatorId: 'u1');

      expect(map.containsKey('restrita_ao_grupo'), isFalse);
      expect(map.containsKey('rodada_id'), isFalse);
    });

    test('candidata envia a restrição junto da Rodada', () {
      final map = NewAction(
        name: 'Ensaio',
        dateTime: DateTime(2027, 1, 1),
        location: 'Sede',
        votingRoundId: 'r1',
        restrictedToGroup: true,
      ).toInsertMap(creatorId: 'u1');

      expect(map['restrita_ao_grupo'], isTrue);
      expect(map['rodada_id'], 'r1');
    });

    test('candidata sem restrição envia false explícito', () {
      final map = NewAction(
        name: 'Ensaio',
        dateTime: DateTime(2027, 1, 1),
        location: 'Sede',
        votingRoundId: 'r1',
      ).toInsertMap(creatorId: 'u1');

      expect(map['restrita_ao_grupo'], isFalse);
    });
  });

  group('Action.canRestrict', () {
    Action acao({String? groupId = 'g1'}) => Action(
          id: 'a1',
          name: 'Reunião',
          dateTime: DateTime(2027, 1, 1),
          location: 'Sede',
          creatorId: 'criador',
          createdAt: DateTime(2026, 1, 1),
          groupId: groupId,
        );

    test('Ação avulsa não é restringível por ninguém', () {
      expect(
        acao(groupId: null).canRestrict('criador',
            isGroupOwner: true, isDistrictAdmin: true),
        isFalse,
      );
    });

    test('criador, Dono do Grupo e Administrador podem — a mesma lista que '
        'edita a Ação', () {
      expect(acao().canRestrict('criador', isGroupOwner: false), isTrue);
      expect(acao().canRestrict('outra', isGroupOwner: true), isTrue);
      expect(
        acao().canRestrict('outra', isGroupOwner: false, isDistrictAdmin: true),
        isTrue,
      );
    });

    test('quem não edita a Ação não pode', () {
      expect(acao().canRestrict('outra', isGroupOwner: false), isFalse);
      expect(acao().canRestrict(null, isGroupOwner: false), isFalse);
    });
  });

  group('Action.fromMap', () {
    test('lê restrita_ao_grupo, e o padrão é público', () {
      Map<String, dynamic> base() => {
            'id': 'a1',
            'nome': 'Reunião',
            'data_hora': '2027-01-01T00:00:00Z',
            'local': 'Sede',
            'criador_id': 'u1',
            'created_at': '2026-01-01T00:00:00Z',
          };

      expect(Action.fromMap(base()).restrictedToGroup, isFalse);
      expect(
        Action.fromMap({...base(), 'restrita_ao_grupo': true}).restrictedToGroup,
        isTrue,
      );
    });
  });
}

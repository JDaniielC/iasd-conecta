import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';
import 'package:iasd_conecta/features/invite/domain/action_invite.dart';

/// Change `convite-para-acao` — o mapeamento da fronteira de idioma e a
/// derivação de "convite em aberto".
///
/// "Em aberto" não é coluna: é derivado de quatro coisas ao mesmo tempo. Cada
/// uma delas some com o convite por um motivo diferente, e é fácil implementar
/// só três. Por isso cada caso tem teste próprio.

Map<String, dynamic> _linha({String? recusadoEm}) => {
      'acao_id': 'a1',
      'convidado_id': 'u2',
      'grupo_id': 'g1',
      'convidante_id': 'u1',
      'created_at': '2026-08-13T10:00:00Z',
      'recusado_em': recusadoEm,
    };

Action _acao({DateTime? dateTime, DateTime? cancelledAt}) => Action(
      id: 'a1',
      name: 'Encontro',
      dateTime: dateTime ?? DateTime(2027, 1, 1, 10),
      local: 'Sede',
      creatorId: 'u1',
      createdAt: DateTime(2026, 1, 1),
      cancelledAt: cancelledAt,
    );

ReceivedInvite _recebido({
  String? recusadoEm,
  Action? acao,
  // `acao: null` cairia no padrão por causa do `??`; este sinalizador é o que
  // deixa o caso "Ação ilegível" ser montado de verdade.
  bool semAcao = false,
  bool confirmada = false,
}) =>
    ReceivedInvite(
      invite: ActionInvite.fromMap(_linha(recusadoEm: recusadoEm)),
      groupName: 'Jovens',
      action: semAcao ? null : (acao ?? _acao()),
      alreadyConfirmed: confirmada,
    );

final _agora = DateTime(2026, 8, 13, 12);

void main() {
  group('ActionInvite.fromMap — chaves em português, campos em inglês', () {
    test('lê as seis colunas', () {
      final i = ActionInvite.fromMap(_linha());
      expect(i.actionId, 'a1');
      expect(i.invitedId, 'u2');
      expect(i.groupId, 'g1');
      expect(i.inviterId, 'u1');
      expect(i.createdAt, DateTime.parse('2026-08-13T10:00:00Z'));
      expect(i.declinedAt, isNull);
      expect(i.isDeclined, isFalse);
    });

    test('recusado_em preenchido vira isDeclined', () {
      final i = ActionInvite.fromMap(_linha(recusadoEm: '2026-08-13T11:00:00Z'));
      expect(i.isDeclined, isTrue);
    });
  });

  group('ReceivedInvite.isOpen', () {
    test('convite novo, Ação futura e sem resposta está em aberto', () {
      expect(_recebido().isOpen(_agora), isTrue);
    });

    test('recusado sai de aberto', () {
      expect(
        _recebido(recusadoEm: '2026-08-13T11:00:00Z').isOpen(_agora),
        isFalse,
      );
    });

    test('já confirmado sai de aberto — aceitar é confirmar presença', () {
      expect(_recebido(confirmada: true).isOpen(_agora), isFalse);
    });

    test('Ação cancelada sai de aberto', () {
      expect(
        _recebido(acao: _acao(cancelledAt: DateTime(2026, 8, 12))).isOpen(_agora),
        isFalse,
      );
    });

    test('Ação encerrada sai de aberto', () {
      // Encerrada = passou de data_hora + 4h, mesmo limiar do banco.
      expect(
        _recebido(acao: _acao(dateTime: DateTime(2026, 8, 13, 5))).isOpen(_agora),
        isFalse,
      );
    });

    test('Ação ilegível sai de aberto — convite para o que não abre', () {
      // Acontece com Ação restrita ao Grupo depois que a pessoa sai dele: o
      // banco deixa de devolver a linha e o embed vem nulo. Mostrar o convite
      // ali seria oferecer algo que a tela seguinte não consegue carregar.
      expect(_recebido(semAcao: true).isOpen(_agora), isFalse);
    });
  });

  group('InviteResult.fromMap', () {
    test('as três classificações do banco', () {
      expect(
        InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'criado'}).outcome,
        InviteOutcome.created,
      );
      expect(
        InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'ja_convidado'})
            .outcome,
        InviteOutcome.alreadyInvited,
      );
      expect(
        InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'nao_participa'})
            .outcome,
        InviteOutcome.notInGroup,
      );
    });

    test('já convidado conta como sucesso — repetir não é falha', () {
      expect(
        InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'ja_convidado'})
            .succeeded,
        isTrue,
      );
      expect(
        InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'nao_participa'})
            .succeeded,
        isFalse,
      );
    });

    test('classificação desconhecida estoura em vez de virar sucesso calado',
        () {
      expect(
        () => InviteResult.fromMap({'usuario_id': 'u2', 'resultado': 'sei_la'}),
        throwsArgumentError,
      );
    });
  });
}

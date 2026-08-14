import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/notification/domain/app_notification.dart';

/// Change `notificacoes-in-app` — mapeamento e derivação de "não lido".
///
/// O tipo desconhecido tem caso próprio: a tabela nasceu genérica de propósito,
/// chat e log de mudanças entram como tipos novos depois, e a migration vai
/// antes do build web. Por alguns minutos o banco pode ter um tipo que o app
/// ainda não desenha — e derrubar a lista inteira por causa disso trocaria "um
/// aviso faltando" por "nenhum aviso".

Map<String, dynamic> _linha(String tipo, {String? lidaEm, String? acaoId}) => {
      'id': 'n1',
      'tipo': tipo,
      'created_at': '2026-08-13T10:00:00Z',
      'ator_id': 'u1',
      'acao_id': acaoId,
      'grupo_id': 'g1',
      'lida_em': lidaEm,
    };

void main() {
  group('mapeamento dos três tipos', () {
    test('toda chave do banco tem tipo Dart, e volta na mesma chave', () {
      const chaves = ['convite_recebido', 'convite_aceito', 'convite_recusado'];
      expect(chaves, hasLength(NotificationType.values.length));
      for (final k in chaves) {
        expect(NotificationType.fromKey(k)?.key, k, reason: k);
      }
    });

    test('tipo desconhecido devolve nulo em vez de estourar', () {
      expect(NotificationType.fromKey('chat_mensagem_nova'), isNull);
      expect(AppNotification.fromMap(_linha('chat_mensagem_nova')), isNull);
    });
  });

  group('não lido', () {
    test('lida_em nulo é não lido; preenchido é lido', () {
      expect(AppNotification.fromMap(_linha('convite_recebido'))!.isUnread, isTrue);
      expect(
        AppNotification.fromMap(_linha('convite_recebido', lidaEm: '2026-08-13T11:00:00Z'))!
            .isUnread,
        isFalse,
      );
    });
  });

  group('frase', () {
    test('os três tipos, com autor e com Grupo', () {
      for (final (tipo, esperado) in [
        ('convite_recebido', 'Ana convidou você — pelo Grupo Jovens'),
        ('convite_aceito', 'Ana aceitou seu convite — pelo Grupo Jovens'),
        ('convite_recusado', 'Ana recusou seu convite — pelo Grupo Jovens'),
      ]) {
        final n = AppNotification.fromMap(_linha(tipo),
            actorName: 'Ana', groupName: 'Jovens')!;
        expect(n.sentence, esperado);
      }
    });

    test('sem autor sai "Alguém", nunca null na frase', () {
      final n = AppNotification.fromMap({..._linha('convite_recebido'), 'ator_id': null})!;
      expect(n.sentence, startsWith('Alguém'));
      expect(n.sentence, isNot(contains('null')));
    });

    test('sem Grupo a frase não sobra com traço solto', () {
      final n = AppNotification.fromMap(_linha('convite_aceito'), actorName: 'Ana')!;
      expect(n.sentence, 'Ana aceitou seu convite');
      expect(n.sentence, isNot(contains('—')));
    });
  });

  group('nome da Ação vem da view', () {
    test('a view expõe acao_nome, e o modelo o lê de lá', () {
      final n = AppNotification.fromMap(
        {..._linha('convite_recebido', acaoId: 'a1'), 'acao_nome': 'Ensaio'},
      )!;
      expect(n.actionName, 'Ensaio');
      expect(n.actionId, 'a1');
    });

    test('sem Ação, sem nome — e sem null', () {
      final n = AppNotification.fromMap(_linha('convite_recebido'))!;
      expect(n.actionName, isNull);
      expect(n.actionId, isNull);
    });
  });
}

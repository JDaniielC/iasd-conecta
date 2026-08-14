import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/change_log/domain/change_log_entry.dart';

/// Change `log-de-mudancas-em-grupo-e-acao` — o mapeamento dos dez tipos e a
/// frase sem sujeito.
///
/// O tipo desconhecido tem teste próprio porque o modo de falha é assimétrico:
/// a migration vai antes do build web, então por alguns minutos o banco pode ter
/// um tipo que o app ainda não desenha. Ignorar a linha faz o histórico aparecer
/// incompleto por um instante; estourar faz a tela sumir.

Map<String, dynamic> _linha(String tipo, {String? autor}) => {
      'id': 'm1',
      'tipo': tipo,
      'created_at': '2026-08-13T10:00:00Z',
      'grupo_id': 'g1',
      'acao_id': null,
      'autor_id': autor,
    };

void main() {
  group('mapeamento dos dez tipos, ida e volta', () {
    test('toda chave do banco tem tipo Dart, e volta na mesma chave', () {
      const chaves = [
        'acao_criada',
        'acao_horario_alterado',
        'acao_local_alterado',
        'acao_cancelada',
        'participacao_entrou',
        'participacao_saiu',
        'confirmacao_confirmado',
        'confirmacao_fila',
        'confirmacao_cancelada',
        'grupo_arquivado',
      ];
      expect(chaves, hasLength(ChangeLogType.values.length));
      for (final k in chaves) {
        final t = ChangeLogType.fromKey(k);
        expect(t, isNotNull, reason: k);
        expect(t!.key, k);
      }
    });

    test('tipo desconhecido devolve nulo em vez de estourar', () {
      expect(ChangeLogType.fromKey('acao_teletransportada'), isNull);
      expect(ChangeLogEntry.fromMap(_linha('acao_teletransportada')), isNull);
    });
  });

  group('frase, com autor e sem', () {
    test('os dez tipos têm frase nos dois casos, e nenhuma sai com null',
        () async {
      for (final t in ChangeLogType.values) {
        final comAutor =
            ChangeLogEntry.fromMap(_linha(t.key, autor: 'u1'), authorName: 'Ana')!;
        final semAutor = ChangeLogEntry.fromMap(_linha(t.key))!;

        expect(comAutor.sentence, contains('Ana'), reason: t.key);
        expect(semAutor.sentence, isNot(contains('Ana')), reason: t.key);
        expect(semAutor.sentence, isNot(contains('null')), reason: t.key);
        // A frase sem sujeito não é a frase com o nome removido: "entrou no
        // Grupo" sozinho não é frase.
        expect(semAutor.sentence.trim(), isNotEmpty, reason: t.key);
        expect(semAutor.sentence[0], semAutor.sentence[0].toUpperCase(),
            reason: '${t.key} — frase sem sujeito precisa começar com maiúscula');
      }
    });

    test('autor nulo em participação sai como "Alguém"', () {
      final e = ChangeLogEntry.fromMap(_linha('participacao_saiu'))!;
      expect(e.sentence, 'Alguém saiu do Grupo');
    });
  });

  test('fromMap lê as colunas do banco', () {
    final e = ChangeLogEntry.fromMap(
      {
        'id': 'm1',
        'tipo': 'acao_horario_alterado',
        'created_at': '2026-08-13T10:00:00Z',
        'grupo_id': 'g1',
        'acao_id': 'a1',
        'autor_id': 'u1',
      },
      authorName: 'Ana',
    )!;
    expect(e.id, 'm1');
    expect(e.type, ChangeLogType.actionTimeChanged);
    expect(e.groupId, 'g1');
    expect(e.actionId, 'a1');
    expect(e.authorId, 'u1');
    expect(e.authorName, 'Ana');
    expect(e.createdAt, DateTime.parse('2026-08-13T10:00:00Z'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/group/domain/group.dart';

/// Feature 014 — o estado "arquivado" lido do banco.
///
/// Grupo arquivado não é Grupo apagado: apagar Grupo não existe no app, porque
/// `rodadas_votacao.grupo_id`, `acoes.grupo_id` e `liderancas.grupo_id` são FKs
/// sem `on delete` e o banco recusa. O que existe é sair de circulação.
Map<String, dynamic> groupRow({
  String? archivedAt,
  String? archivedBy,
}) {
  return {
    'id': 'grupo-1',
    'nome': 'SevenBikers',
    'categoria': 'Esporte',
    'horario': 'domingos 7h',
    'local': 'Praça Matriz',
    'detalhes': null,
    'igreja_id': 'igreja-1',
    'dono_id': 'uid-dono',
    'created_at': '2026-07-01T10:00:00.000Z',
    'arquivado_em': archivedAt,
    'arquivado_por': archivedBy,
  };
}

void main() {
  test('Grupo sem arquivado_em está ativo', () {
    final group = Group.fromMap(groupRow());

    expect(group.isArchived, isFalse);
    expect(group.archivedAt, isNull);
    expect(group.archivedBy, isNull);
  });

  test('Grupo com arquivado_em está arquivado, e sabe quem arquivou', () {
    final group = Group.fromMap(groupRow(
      archivedAt: '2026-08-09T15:00:00.000Z',
      archivedBy: 'uid-admin',
    ));

    expect(group.isArchived, isTrue);
    expect(group.archivedAt, DateTime.parse('2026-08-09T15:00:00.000Z'));
    // Quem arquivou é o que o Administrador do distrito precisa para decidir
    // se desarquiva.
    expect(group.archivedBy, 'uid-admin');
  });

  test('as chaves lidas são as colunas do banco, em português', () {
    // Se alguém renomear a coluna e esquecer o mapa, isto falha aqui e não
    // numa tela em produção.
    final group = Group.fromMap(groupRow(archivedAt: '2026-08-09T15:00:00.000Z'));
    expect(group.isArchived, isTrue);
  });
}

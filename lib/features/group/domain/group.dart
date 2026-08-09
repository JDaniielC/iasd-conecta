/// Dados de um Grupo ainda não enviado ao banco (formulário de criação).
///
/// `igrejaId` e `donoId` não fazem parte do formulário — são preenchidos
/// pelo repositório a partir da sessão atual (FR-002, FR-003).
class NewGroup {
  const NewGroup({
    required this.name,
    required this.category,
    this.schedule,
    this.local,
    this.details,
  });

  final String name;
  final String category;
  final String? schedule;
  final String? local;
  final String? details;

  bool get isReadyToSubmit => name.trim().isNotEmpty && category.trim().isNotEmpty;

  Map<String, dynamic> toInsertMap({
    required String ownerId,
    String? churchId,
  }) {
    return {
      'nome': name.trim(),
      'categoria': category.trim(),
      'horario': (schedule?.trim().isEmpty ?? true) ? null : schedule!.trim(),
      'local': (local?.trim().isEmpty ?? true) ? null : local!.trim(),
      'detalhes': (details?.trim().isEmpty ?? true) ? null : details!.trim(),
      'dono_id': ownerId,
      'igreja_id': churchId,
    };
  }
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.category,
    required this.ownerId,
    required this.createdAt,
    this.schedule,
    this.local,
    this.details,
    this.churchId,
  });

  final String id;
  final String name;
  final String category;
  final String? schedule;
  final String? local;
  final String? details;
  final String? churchId;
  final String ownerId;
  final DateTime createdAt;

  bool isOwner(String? currentUserId) => currentUserId != null && currentUserId == ownerId;

  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['nome'] as String,
      category: map['categoria'] as String,
      schedule: map['horario'] as String?,
      local: map['local'] as String?,
      details: map['detalhes'] as String?,
      churchId: map['igreja_id'] as String?,
      ownerId: map['dono_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

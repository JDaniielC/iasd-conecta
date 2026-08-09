class GroupCategory {
  const GroupCategory({required this.id, required this.nome});

  final String id;
  final String nome;

  factory GroupCategory.fromMap(Map<String, dynamic> map) {
    return GroupCategory(id: map['id'] as String, nome: map['nome'] as String);
  }
}

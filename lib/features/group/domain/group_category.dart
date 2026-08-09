class GroupCategory {
  const GroupCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory GroupCategory.fromMap(Map<String, dynamic> map) {
    return GroupCategory(id: map['id'] as String, name: map['nome'] as String);
  }
}

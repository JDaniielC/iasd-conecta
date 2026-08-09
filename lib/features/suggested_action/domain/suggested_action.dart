class SuggestedAction {
  const SuggestedAction({required this.id, required this.categoryId, required this.name});

  final String id;
  final String categoryId;
  final String name;

  factory SuggestedAction.fromMap(Map<String, dynamic> map) {
    return SuggestedAction(
      id: map['id'] as String,
      categoryId: map['categoria_id'] as String,
      name: map['nome'] as String,
    );
  }
}

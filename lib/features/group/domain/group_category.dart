class CategoriaGrupo {
  const CategoriaGrupo({required this.id, required this.nome});

  final String id;
  final String nome;

  factory CategoriaGrupo.fromMap(Map<String, dynamic> map) {
    return CategoriaGrupo(id: map['id'] as String, nome: map['nome'] as String);
  }
}

class Igreja {
  const Igreja({required this.id, required this.nome});

  final String id;
  final String nome;

  factory Igreja.fromMap(Map<String, dynamic> map) {
    return Igreja(id: map['id'] as String, nome: map['nome'] as String);
  }
}

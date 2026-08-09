/// Dados de um Grupo ainda não enviado ao banco (formulário de criação).
///
/// `igrejaId` e `donoId` não fazem parte do formulário — são preenchidos
/// pelo repositório a partir da sessão atual (FR-002, FR-003).
class NovoGrupo {
  const NovoGrupo({
    required this.nome,
    required this.categoria,
    this.horario,
    this.local,
    this.detalhes,
  });

  final String nome;
  final String categoria;
  final String? horario;
  final String? local;
  final String? detalhes;

  bool get prontoParaEnviar => nome.trim().isNotEmpty && categoria.trim().isNotEmpty;

  Map<String, dynamic> toInsertMap({
    required String donoId,
    String? igrejaId,
  }) {
    return {
      'nome': nome.trim(),
      'categoria': categoria.trim(),
      'horario': (horario?.trim().isEmpty ?? true) ? null : horario!.trim(),
      'local': (local?.trim().isEmpty ?? true) ? null : local!.trim(),
      'detalhes': (detalhes?.trim().isEmpty ?? true) ? null : detalhes!.trim(),
      'dono_id': donoId,
      'igreja_id': igrejaId,
    };
  }
}

class Grupo {
  const Grupo({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.donoId,
    required this.createdAt,
    this.horario,
    this.local,
    this.detalhes,
    this.igrejaId,
  });

  final String id;
  final String nome;
  final String categoria;
  final String? horario;
  final String? local;
  final String? detalhes;
  final String? igrejaId;
  final String donoId;
  final DateTime createdAt;

  bool souDono(String? usuarioAtualId) => usuarioAtualId != null && usuarioAtualId == donoId;

  factory Grupo.fromMap(Map<String, dynamic> map) {
    return Grupo(
      id: map['id'] as String,
      nome: map['nome'] as String,
      categoria: map['categoria'] as String,
      horario: map['horario'] as String?,
      local: map['local'] as String?,
      detalhes: map['detalhes'] as String?,
      igrejaId: map['igreja_id'] as String?,
      donoId: map['dono_id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

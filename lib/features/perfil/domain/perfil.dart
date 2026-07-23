enum Genero {
  masculino,
  feminino;

  String get valorBanco => name;
}

const _idadeMaioridade = 18;

/// Dados de um Perfil ainda não enviado ao banco (formulário de cadastro).
///
/// A invariante "menor de idade precisa de Apelido" (FR-005) é espelhada aqui
/// só para feedback imediato na UI — quem garante de verdade é a constraint
/// `apelido_obrigatorio_menor` no banco (ver contracts/schema.sql).
class Perfil {
  const Perfil({
    required this.nome,
    required this.genero,
    required this.idade,
    required this.consentimentoLgpdAceito,
    this.apelido,
    this.igrejaId,
    this.telefone,
  });

  final String nome;
  final Genero genero;
  final int idade;
  final bool consentimentoLgpdAceito;
  final String? apelido;
  final String? igrejaId;
  final String? telefone;

  bool get menorDeIdade => idade < _idadeMaioridade;

  bool get precisaDeApelido => menorDeIdade && (apelido == null || apelido!.trim().isEmpty);

  /// Verdadeiro só quando o formulário está pronto para ser enviado —
  /// consentimento aceito, nome preenchido, e Apelido presente se for menor.
  bool get prontoParaEnviar =>
      consentimentoLgpdAceito && nome.trim().isNotEmpty && !precisaDeApelido;

  Map<String, dynamic> toInsertMap({required String id}) {
    return {
      'id': id,
      'nome': nome.trim(),
      'apelido': apelido?.trim().isEmpty ?? true ? null : apelido!.trim(),
      'igreja_id': igrejaId,
      'telefone': telefone?.trim().isEmpty ?? true ? null : telefone!.trim(),
      'genero': genero.valorBanco,
      'idade': idade,
      'consentimento_lgpd_aceito_em': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

/// Projeção pública de um Perfil (via RPC `perfil_publico`) — nunca contém
/// idade nem telefone (FR-004).
class PerfilPublico {
  const PerfilPublico({
    required this.id,
    required this.nomeExibido,
    this.igrejaId,
  });

  final String id;
  final String nomeExibido;
  final String? igrejaId;

  factory PerfilPublico.fromMap(Map<String, dynamic> map) {
    return PerfilPublico(
      id: map['id'] as String,
      nomeExibido: map['nome_exibido'] as String,
      igrejaId: map['igreja_id'] as String?,
    );
  }
}

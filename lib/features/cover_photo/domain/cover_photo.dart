/// A imagem de capa de um Grupo/Ministério **ou** de uma Ação.
///
/// Exatamente um dono: [groupId] e [actionId] nunca são ambos preenchidos nem
/// ambos nulos. A regra é do banco (`fotos_capa_um_dono`), não da disciplina de
/// quem escreve o código — aqui ela é só espelhada.
///
/// **Não existe foto de Perfil.** A imagem ilustra o Grupo ou a Ação, nunca a
/// pessoa. Se um dia aparecer capa de pessoa, é feature nova, com decisão de
/// privacidade própria.
class CoverPhoto {
  const CoverPhoto({
    required this.id,
    required this.path,
    required this.uploadedBy,
    required this.createdAt,
    this.groupId,
    this.actionId,
  });

  factory CoverPhoto.fromMap(Map<String, dynamic> map) {
    return CoverPhoto(
      id: map['id'] as String,
      groupId: map['grupo_id'] as String?,
      actionId: map['acao_id'] as String?,
      path: map['caminho'] as String,
      uploadedBy: map['enviada_por'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String? groupId;
  final String? actionId;

  /// Caminho dentro do bucket, no formato `grupo/<uuid>/<arquivo>` ou
  /// `acao/<uuid>/<arquivo>`. **O caminho carrega o dono** e a política de
  /// armazenamento confere o segmento do meio (research D-007) — mudar o
  /// formato aqui sem mudar a política deixa a escrita passar a valer para
  /// qualquer prefixo.
  final String path;

  /// Quem enviou. Serve para prestação de contas e para a regra de exclusão de
  /// conta (FR-024). **Não decide permissão**: quem controla a capa é quem
  /// administra o Grupo/Ação hoje (FR-003), não quem enviou.
  final String uploadedBy;

  final DateTime createdAt;
}

/// Teto de tamanho, em bytes. **Gêmeo de `file_size_limit` do bucket**
/// (`20260810100000_foto_de_capa.sql`), e os dois mudam juntos.
///
/// Existe do lado do cliente para a pessoa saber o limite **antes** do envio
/// (FR-009), e não descobrir no erro do fornecedor, em inglês, depois de
/// esperar o upload de um arquivo grande demais.
const coverPhotoMaxBytes = 5 * 1024 * 1024;

/// Formatos aceitos. **Gêmeos de `allowed_mime_types` do bucket**, mesma regra
/// de mudar junto.
const coverPhotoAllowedMimeTypes = <String>{
  'image/jpeg',
  'image/png',
  'image/webp',
};

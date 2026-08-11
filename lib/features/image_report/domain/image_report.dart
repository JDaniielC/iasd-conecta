/// Uma denúncia sobre uma imagem de capa.
///
/// **Pode não ter autor** ([reporterId] nulo), e isso é o desenho, não uma
/// lacuna: o caso que motivou a feature é uma mãe sem cadastro vendo a foto da
/// filha. Exigir cadastro dela para pedir a retirada seria exigir que ela
/// entregue os próprios dados para retirar os da filha.
class ImageReport {
  const ImageReport({
    required this.id,
    required this.photoId,
    required this.reason,
    required this.state,
    required this.createdAt,
    this.reporterId,
  });

  factory ImageReport.fromMap(Map<String, dynamic> map) {
    return ImageReport(
      id: map['id'] as String,
      photoId: map['foto_id'] as String,
      reason: map['motivo'] as String,
      reporterId: map['denunciante_id'] as String?,
      state: ImageReportState.fromDb(map['estado'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String photoId;
  final String reason;

  /// **Nunca exibido a quem enviou a imagem nem a Usuário comum** (FR-020). O
  /// banco já garante — não existe política de select fora do Administrador do
  /// distrito. Aqui o campo existe só para o Administrador conseguir julgar
  /// denúncia em massa.
  final String? reporterId;

  final ImageReportState state;
  final DateTime createdAt;
}

enum ImageReportState {
  pending('pendente'),
  imageRemoved('imagem_removida'),
  dismissed('improcedente');

  const ImageReportState(this.dbValue);

  /// Valor gravado no banco, em português — a fronteira de idioma do
  /// Princípio I: identificador em inglês, chave de banco em português.
  final String dbValue;

  static ImageReportState fromDb(String value) =>
      ImageReportState.values.firstWhere((s) => s.dbValue == value);
}

/// As denúncias pendentes **sobre uma mesma imagem**, agrupadas.
///
/// A lista do Administrador é por **imagem**, não por denúncia (FR-018). Dez
/// pessoas denunciando a mesma foto são um item com contagem 10, e não dez
/// itens — resolver o item resolve todas. Sem isso, uma imagem que incomodou
/// muita gente enterraria as outras pendências.
class ReportedImage {
  const ReportedImage({
    required this.photoId,
    required this.reportCount,
    required this.reasons,
    required this.groupId,
    required this.actionId,
    required this.path,
  });

  final String photoId;
  final int reportCount;

  /// Os motivos escritos, em ordem de chegada. Sem autor: [ImageReport.reporterId]
  /// não vem para cá, porque nada nesta tela precisa dele.
  final List<String> reasons;

  final String? groupId;
  final String? actionId;
  final String path;
}

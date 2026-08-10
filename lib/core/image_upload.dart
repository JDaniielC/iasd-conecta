import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Escolha e validação de imagem, em um lugar só.
///
/// **A diferença entre web e mobile morre aqui** e não vaza para o resto do
/// app (research D-002). Em mobile o seletor devolve um caminho de arquivo; em
/// web não existe caminho. Código escrito contra o caminho compila e quebra
/// justamente em produção, que é onde este app está. Por isso tudo daqui para
/// dentro trabalha com **bytes**.
///
/// A validação acontece **antes de qualquer escrita** (FR-009). Recusar depois
/// de publicar seria publicar — e o que se publica aqui é imagem pública, que
/// qualquer pessoa na internet vê.
class ImageUpload {
  ImageUpload({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Abre o seletor e devolve a imagem já validada, ou `null` se a pessoa
  /// desistiu.
  ///
  /// Lança [ImageRejected] quando o arquivo escolhido não serve — cada motivo
  /// com a sua frase, porque "imagem inválida" não diz à pessoa o que fazer.
  Future<PickedImage?> pick({
    required int maxBytes,
    required Set<String> allowedMimeTypes,
  }) async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    return validate(
      bytes: bytes,
      maxBytes: maxBytes,
      allowedMimeTypes: allowedMimeTypes,
    );
  }

  /// Separada de [pick] para ser testável sem seletor de arquivo.
  static PickedImage validate({
    required Uint8List bytes,
    required int maxBytes,
    required Set<String> allowedMimeTypes,
  }) {
    if (bytes.isEmpty) {
      throw const ImageRejected(
        'Esse arquivo está vazio. Escolha outra imagem.',
      );
    }

    // Tamanho antes de formato: é o motivo mais comum, e a pessoa consegue
    // agir sobre ele (tirar foto menor, escolher outra).
    if (bytes.length > maxBytes) {
      final limitMb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw ImageRejected(
        'Essa imagem é grande demais. O limite é $limitMb MB.',
      );
    }

    // O tipo vem dos PRIMEIROS BYTES do arquivo, não da extensão do nome.
    //
    // Extensão é sugestão de quem nomeou: renomear um PDF para `.jpg` passaria
    // por qualquer checagem de nome, e o que chegaria ao bucket público seria
    // um arquivo que o navegador não desenha — a capa vira um retângulo
    // quebrado que ninguém consegue explicar. Ler a assinatura é também a
    // checagem de legibilidade que FR-009 pede, sem precisar decodificar a
    // imagem inteira.
    final mimeType = _sniffMimeType(bytes);
    if (mimeType == null) {
      throw const ImageRejected(
        'Não consegui ler esse arquivo como imagem. Escolha uma foto ou uma '
        'arte em JPG, PNG ou WEBP.',
      );
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw const ImageRejected(
        'Esse formato não é aceito. Envie JPG, PNG ou WEBP.',
      );
    }

    return PickedImage(bytes: bytes, mimeType: mimeType);
  }

  /// Assinatura de arquivo ("magic bytes") dos três formatos aceitos.
  ///
  /// Os mesmos três que o bucket declara em `allowed_mime_types`. Se um lado
  /// mudar sem o outro, o sintoma é o envio ser aceito aqui e recusado lá, com
  /// mensagem do fornecedor em inglês — por isso os dois estão amarrados por
  /// [coverPhotoAllowedMimeTypes], que a chamada passa.
  static String? _sniffMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    // WEBP é um contêiner RIFF: 'RIFF' <4 bytes de tamanho> 'WEBP'.
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}

/// Uma imagem escolhida e já validada. Só existe se passou por
/// [ImageUpload.validate].
class PickedImage {
  const PickedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// Descoberto lendo os bytes, não o nome do arquivo.
  final String mimeType;

  /// Extensão correspondente ao [mimeType], para compor o caminho no bucket.
  String get extension => switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'bin',
      };
}

/// Motivo pelo qual a imagem não serve, já em português e já pronto para a
/// tela. A tela não traduz nada: se precisar traduzir, a mensagem nasceu no
/// lugar errado.
class ImageRejected implements Exception {
  const ImageRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

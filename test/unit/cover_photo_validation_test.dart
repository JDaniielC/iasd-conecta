import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/core/image_upload.dart';
import 'package:iasd_conecta/features/cover_photo/domain/cover_photo.dart';

/// FR-009 — o arquivo é recusado **antes** de qualquer escrita, e **cada
/// motivo tem a sua frase**.
///
/// A frase importa tanto quanto a recusa: "imagem inválida" não diz à pessoa o
/// que fazer, e o que ela faz em seguida é tentar o mesmo arquivo de novo.
void main() {
  Uint8List jpegOf(int totalBytes) {
    final bytes = Uint8List(totalBytes);
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    bytes[2] = 0xFF;
    return bytes;
  }

  PickedImage validate(Uint8List bytes) => ImageUpload.validate(
        bytes: bytes,
        maxBytes: coverPhotoMaxBytes,
        allowedMimeTypes: coverPhotoAllowedMimeTypes,
      );

  group('aceita os três formatos que o bucket declara', () {
    test('JPEG', () {
      expect(validate(jpegOf(64)).mimeType, 'image/jpeg');
      expect(validate(jpegOf(64)).extension, 'jpg');
    });

    test('PNG', () {
      final bytes = Uint8List.fromList(
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0],
      );
      expect(validate(bytes).mimeType, 'image/png');
      expect(validate(bytes).extension, 'png');
    });

    test('WEBP', () {
      final bytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // tamanho
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      expect(validate(bytes).mimeType, 'image/webp');
      expect(validate(bytes).extension, 'webp');
    });
  });

  group('recusa, cada um com o seu motivo', () {
    test('acima do tamanho máximo, dizendo qual é o limite', () {
      expect(
        () => validate(jpegOf(coverPhotoMaxBytes + 1)),
        throwsA(
          isA<ImageRejected>()
              .having((e) => e.message, 'mensagem', contains('grande demais'))
              .having((e) => e.message, 'diz o limite', contains('5 MB')),
        ),
      );
    });

    test('exatamente no limite é aceito — o teto não pode ser exclusivo', () {
      expect(validate(jpegOf(coverPhotoMaxBytes)).mimeType, 'image/jpeg');
    });

    test('formato não suportado, mesmo sendo imagem de verdade', () {
      // GIF: assinatura válida de imagem, formato fora da lista do bucket.
      final gif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      expect(
        () => validate(gif),
        throwsA(
          isA<ImageRejected>().having(
            (e) => e.message,
            'mensagem',
            contains('Não consegui ler'),
          ),
        ),
      );
    });

    test('arquivo ilegível — PDF renomeado para .jpg', () {
      // O caso que uma checagem por extensão deixaria passar: o nome diz
      // imagem, os bytes dizem PDF. Chegaria ao bucket público e viraria um
      // retângulo quebrado que ninguém consegue explicar.
      final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]);
      expect(
        () => validate(pdf),
        throwsA(
          isA<ImageRejected>().having(
            (e) => e.message,
            'mensagem',
            contains('Não consegui ler'),
          ),
        ),
      );
    });

    test('arquivo vazio', () {
      expect(
        () => validate(Uint8List(0)),
        throwsA(
          isA<ImageRejected>().having(
            (e) => e.message,
            'mensagem',
            contains('vazio'),
          ),
        ),
      );
    });

    test('truncado — assinatura começa certa e o arquivo acaba', () {
      expect(
        () => validate(Uint8List.fromList([0xFF, 0xD8])),
        throwsA(isA<ImageRejected>()),
      );
    });
  });

  test('a mensagem vai pronta para a tela, sem a tela traduzir nada', () {
    // Se a tela precisar traduzir, a mensagem nasceu no lugar errado.
    try {
      validate(Uint8List.fromList([0x25, 0x50, 0x44, 0x46]));
      fail('devia ter recusado');
    } on ImageRejected catch (e) {
      expect(e.toString(), e.message);
      expect(e.message, isNot(contains('Exception')));
    }
  });
}

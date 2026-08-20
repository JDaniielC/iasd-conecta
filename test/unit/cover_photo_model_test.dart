import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/cover_photo/domain/cover_photo.dart';

/// `CoverPhoto` e as constantes de capa — estavam em 2/14 linhas.
///
/// O que importa aqui é o **caminho**, que carrega o dono: a política de
/// armazenamento confere o segmento do meio, então uma mudança de formato sem
/// a política correspondente deixaria a escrita valer para qualquer prefixo.

void main() {
  group('CoverPhoto.fromMap', () {
    test('lê capa de Grupo, com acao_id nulo', () {
      final photo = CoverPhoto.fromMap({
        'id': 'f1',
        'grupo_id': 'g1',
        'acao_id': null,
        'caminho': 'grupo/g1/capa.jpg',
        'enviada_por': 'quem-enviou',
        'created_at': '2026-08-10T12:00:00Z',
      });

      expect(photo.id, 'f1');
      expect(photo.groupId, 'g1');
      expect(photo.actionId, isNull);
      expect(photo.path, 'grupo/g1/capa.jpg');
      expect(photo.uploadedBy, 'quem-enviou');
      expect(photo.createdAt, DateTime.parse('2026-08-10T12:00:00Z'));
    });

    test('lê capa de Ação, com grupo_id nulo', () {
      final photo = CoverPhoto.fromMap({
        'id': 'f2',
        'grupo_id': null,
        'acao_id': 'a1',
        'caminho': 'acao/a1/capa.png',
        'enviada_por': 'quem-enviou',
        'created_at': '2026-08-10T12:00:00Z',
      });

      expect(photo.groupId, isNull);
      expect(photo.actionId, 'a1');
    });

    test('o caminho começa pelo segmento que nomeia o dono', () {
      // `fotos_capa_um_dono` no banco garante exatamente um dono; o caminho
      // é o que a política de armazenamento confere.
      final group = CoverPhoto.fromMap({
        'id': 'f1',
        'grupo_id': 'g1',
        'acao_id': null,
        'caminho': 'grupo/g1/capa.jpg',
        'enviada_por': 'u',
        'created_at': '2026-08-10T12:00:00Z',
      });
      expect(group.path.split('/').first, 'grupo');
      expect(group.path.split('/')[1], group.groupId);
    });
  });

  group('Limites que a pessoa precisa saber ANTES do envio', () {
    test('o teto de tamanho é 5 MB', () {
      expect(coverPhotoMaxBytes, 5 * 1024 * 1024);
    });

    test('os formatos aceitos são de imagem, e nenhum deles é vetor ou SVG', () {
      // SVG carrega script; aceitar um seria abrir execução de código em
      // arquivo servido a qualquer pessoa na internet.
      expect(coverPhotoAllowedMimeTypes, isNotEmpty);
      for (final mime in coverPhotoAllowedMimeTypes) {
        expect(mime, startsWith('image/'));
      }
      expect(coverPhotoAllowedMimeTypes, isNot(contains('image/svg+xml')));
    });
  });

  group('CoverPhotoUploadFailed: as três etapas deixam estados opostos', () {
    test('falha ao enviar o arquivo não perde capa nenhuma', () {
      const failure = CoverPhotoUploadFailed(CoverPhotoUploadStage.sendingFile);
      expect(failure.previousPhotoLost, isFalse);
    });

    test('falha ao gravar a linha PODE ter perdido a capa anterior', () {
      const failure = CoverPhotoUploadFailed(
        CoverPhotoUploadStage.savingRecord,
        previousPhotoLost: true,
      );
      expect(failure.stage, CoverPhotoUploadStage.savingRecord);
      expect(failure.previousPhotoLost, isTrue);
    });

    test('toString carrega etapa e perda — é o que aparece em log de erro', () {
      const failure = CoverPhotoUploadFailed(
        CoverPhotoUploadStage.removingPrevious,
        previousPhotoLost: false,
      );
      expect(failure.toString(), contains('removingPrevious'));
      expect(failure.toString(), contains('previousPhotoLost: false'));
    });
  });
}

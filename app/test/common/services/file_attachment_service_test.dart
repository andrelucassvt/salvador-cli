import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/common/services/file_attachment_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('salvador_attach_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('FileAttachmentService.readContent', () {
    test('whenFileIsSmallText_returnsContent', () {
      final file = File('${tempDir.path}/nota.txt')
        ..writeAsStringSync('ola mundo');
      const service = FileAttachmentService();

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentContent>());
      expect((result as AttachmentContent).content, 'ola mundo');
    });

    test('whenFileDoesNotExist_returnsRejected', () {
      const service = FileAttachmentService();

      final result = service.readContent('${tempDir.path}/inexistente.txt');

      expect(result, isA<AttachmentRejected>());
    });

    test('whenFileExceedsMaxBytes_returnsRejected', () {
      final file = File('${tempDir.path}/grande.txt')
        ..writeAsStringSync('0123456789');
      const service = FileAttachmentService(maxFileBytes: 4);

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentRejected>());
      expect((result as AttachmentRejected).reason, contains('excede'));
    });

    test('whenFileIsBinary_returnsRejected', () {
      final file = File('${tempDir.path}/bin.dat')
        ..writeAsBytesSync([0, 1, 2, 3]);
      const service = FileAttachmentService();

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentRejected>());
      expect((result as AttachmentRejected).reason, contains('binário'));
    });

    test('whenFileIsNotValidUtf8_returnsRejected', () {
      final file = File('${tempDir.path}/invalido.txt')
        ..writeAsBytesSync([0xC3, 0x28]);
      const service = FileAttachmentService();

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentRejected>());
      expect((result as AttachmentRejected).reason, contains('UTF-8'));
    });

    test('whenFileIsImage_returnsBase64WithMimeType', () {
      final file = File('${tempDir.path}/foto.png')
        ..writeAsBytesSync([0, 1, 2, 3]);
      const service = FileAttachmentService();

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentImage>());
      expect((result as AttachmentImage).mimeType, 'image/png');
      expect(result.base64, base64Encode([0, 1, 2, 3]));
    });

    test('whenImageExceedsMaxImageBytes_returnsRejected', () {
      final file = File('${tempDir.path}/foto.jpg')
        ..writeAsStringSync('0123456789');
      const service = FileAttachmentService(maxImageBytes: 4);

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentRejected>());
      expect((result as AttachmentRejected).reason, contains('excede'));
    });

    test('whenImageExceedsMaxFileBytesButNotMaxImageBytes_returnsContent', () {
      final file = File('${tempDir.path}/foto.gif')
        ..writeAsBytesSync(List.filled(1024, 1));
      const service = FileAttachmentService(maxFileBytes: 4);

      final result = service.readContent(file.path);

      expect(result, isA<AttachmentImage>());
    });
  });
}

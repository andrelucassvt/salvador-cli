import 'package:flutter/foundation.dart';

/// Conteudo renderizavel do preview, com metadados leves.
@immutable
class FilePreviewEntity {
  const FilePreviewEntity({
    required this.path,
    required this.content,
    required this.lineCount,
    required this.sizeBytes,
    required this.language,
  });

  final String path;
  final String content;
  final int lineCount;
  final int sizeBytes;
  final String language;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilePreviewEntity &&
          path == other.path &&
          content == other.content &&
          lineCount == other.lineCount &&
          sizeBytes == other.sizeBytes &&
          language == other.language;

  @override
  int get hashCode =>
      Object.hash(path, content, lineCount, sizeBytes, language);

  @override
  String toString() =>
      'FilePreviewEntity(path: $path, lineCount: $lineCount, '
      'sizeBytes: $sizeBytes, language: $language)';
}

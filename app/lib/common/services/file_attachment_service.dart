import 'dart:convert';
import 'dart:io';

sealed class AttachmentReadResult {
  const AttachmentReadResult();
}

class AttachmentContent extends AttachmentReadResult {
  const AttachmentContent(this.content);

  final String content;
}

class AttachmentRejected extends AttachmentReadResult {
  const AttachmentRejected(this.reason);

  final String reason;
}

/// Imagem lida como bytes brutos codificados em base64 (sem prefixo
/// `data:`), pronta para o campo `images` de `AgentMessage`.
class AttachmentImage extends AttachmentReadResult {
  const AttachmentImage(this.base64, this.mimeType);

  final String base64;
  final String mimeType;
}

/// Lê e valida um anexo escolhido pelo usuário via picker nativo. Ao
/// contrário de `FileMentionService` (pacote `salvador_cli`), o caminho não
/// precisa estar confinado a nenhuma raiz de workspace — a escolha já veio
/// de uma ação explícita do usuário, não de um `@` interpretado do modelo.
class FileAttachmentService {
  const FileAttachmentService({
    this.maxFileBytes = 512 * 1024,
    this.maxImageBytes = 8 * 1024 * 1024,
  });

  final int maxFileBytes;
  final int maxImageBytes;

  static const Map<String, String> _imageMimeTypes = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
  };

  AttachmentReadResult readContent(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const AttachmentRejected('arquivo inexistente');
    }

    final mimeType = _imageMimeTypes[_extensionOf(path)];
    final size = file.lengthSync();

    if (mimeType != null) {
      if (size > maxImageBytes) {
        return AttachmentRejected(
          '${_formatBytes(size)} excede o limite de '
          '${_formatBytes(maxImageBytes)}',
        );
      }
      return AttachmentImage(base64Encode(file.readAsBytesSync()), mimeType);
    }

    if (size > maxFileBytes) {
      return AttachmentRejected(
        '${_formatBytes(size)} excede o limite de '
        '${_formatBytes(maxFileBytes)}',
      );
    }

    final bytes = file.readAsBytesSync();
    if (bytes.contains(0)) {
      return const AttachmentRejected('arquivo binário');
    }

    try {
      return AttachmentContent(utf8.decode(bytes));
    } on FormatException {
      return const AttachmentRejected('conteúdo não é UTF-8');
    }
  }

  static String _extensionOf(String path) {
    final name = File(path).uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot).toLowerCase();
  }

  static String _formatBytes(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(0)} KiB';
}

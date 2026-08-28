import 'dart:convert';
import 'dart:io';

class ActiveFileMention {
  const ActiveFileMention({required this.start, required this.query});

  final int start;
  final String query;
}

class MentionExpansion {
  const MentionExpansion({
    required this.prompt,
    this.files = const [],
    this.warnings = const [],
  });

  final String prompt;
  final List<String> files;
  final List<String> warnings;
}

/// Finds project files for inline `@path` completion and adds explicitly
/// mentioned file contents to the model prompt.
class FileMentionService {
  FileMentionService(Directory root, {this.maxFileBytes = 512 * 1024})
    : root = root.absolute;

  final Directory root;
  final int maxFileBytes;
  List<String>? _cachedPaths;

  /// Diretorios que nao entram na indexacao nem no painel de arquivos.
  static const ignoredDirectories = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'node_modules',
  };

  /// Rebuilds the completion index. The editor calls this before displaying a
  /// new prompt, so filesystem traversal never pauses an in-progress line.
  void refresh() => _cachedPaths = _discoverFiles();

  ActiveFileMention? activeMention(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final beforeCursor = text.substring(0, cursor);
    final at = beforeCursor.lastIndexOf('@');
    if (at < 0) return null;
    if (at > 0 && !_isMentionBoundary(beforeCursor[at - 1])) return null;

    final query = beforeCursor.substring(at + 1);
    if (query.contains(RegExp(r'\s'))) return null;
    return ActiveFileMention(start: at, query: query);
  }

  List<String> suggest(String query, {int limit = 6}) {
    final normalized = query.toLowerCase();
    final buckets = List.generate(4, (_) => <String>[]);
    for (final path in _cachedPaths ??= _discoverFiles()) {
      if (!path.toLowerCase().contains(normalized)) continue;
      final bucket = buckets[_matchScore(path, normalized)];
      if (bucket.length < limit) bucket.add(path);
    }
    return buckets
        .expand((bucket) => bucket)
        .take(limit)
        .toList(growable: false);
  }

  MentionExpansion expand(String input) {
    final paths = _mentionedPaths(input);
    if (paths.isEmpty) return MentionExpansion(prompt: input);

    final included = <String>[];
    final warnings = <String>[];
    final context = StringBuffer();
    for (final path in paths) {
      final file = _safeFile(path);
      if (file == null) {
        warnings.add('@$path ignorado: arquivo inexistente ou fora da raiz.');
        continue;
      }

      try {
        final size = file.lengthSync();
        if (size > maxFileBytes) {
          warnings.add(
            '@$path ignorado: ${_formatBytes(size)} excede o limite de '
            '${_formatBytes(maxFileBytes)}.',
          );
          continue;
        }
        final bytes = file.readAsBytesSync();
        if (bytes.contains(0)) {
          warnings.add('@$path ignorado: arquivo binario.');
          continue;
        }
        final content = utf8.decode(bytes);
        included.add(path);
        context
          ..writeln('\n--- arquivo mencionado: $path ---')
          ..writeln(content)
          ..writeln('--- fim do arquivo: $path ---');
      } on FormatException {
        warnings.add('@$path ignorado: conteudo nao e UTF-8.');
      } on FileSystemException catch (error) {
        warnings.add('@$path ignorado: ${error.message}.');
      }
    }

    if (included.isEmpty) {
      return MentionExpansion(prompt: input, warnings: warnings);
    }
    return MentionExpansion(
      prompt:
          '$input\n\nUse o conteudo abaixo como contexto dos arquivos '
          'mencionados pelo usuario.${context.toString()}',
      files: List.unmodifiable(included),
      warnings: List.unmodifiable(warnings),
    );
  }

  List<String> _discoverFiles() {
    final paths = <String>[];

    void visit(Directory directory, String prefix) {
      List<FileSystemEntity> entries;
      try {
        entries = directory.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final entry in entries) {
        final name = entry.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        final relative = prefix.isEmpty ? name : '$prefix/$name';
        if (entry is File) {
          paths.add(relative);
        } else if (entry is Directory && !ignoredDirectories.contains(name)) {
          visit(entry, relative);
        }
      }
    }

    visit(root, '');
    paths.sort();
    return paths;
  }

  File? _safeFile(String relativePath) {
    if (relativePath.isEmpty) return null;
    final candidate = File(
      '${root.path}${Platform.pathSeparator}$relativePath',
    );
    if (!candidate.existsSync()) return null;
    try {
      final rootPath = root.resolveSymbolicLinksSync();
      final resolved = candidate.resolveSymbolicLinksSync();
      final prefix = rootPath.endsWith(Platform.pathSeparator)
          ? rootPath
          : '$rootPath${Platform.pathSeparator}';
      if (resolved != rootPath && !resolved.startsWith(prefix)) return null;
      return File(resolved);
    } on FileSystemException {
      return null;
    }
  }

  static List<String> _mentionedPaths(String input) {
    final result = <String>[];
    final seen = <String>{};
    final pattern = RegExp(r'(?:^|[\s(\[])@(?:"([^"]+)"|([^\s)\],;]+))');
    for (final match in pattern.allMatches(input)) {
      final path = match.group(1) ?? match.group(2);
      if (path != null && path.isNotEmpty && seen.add(path)) result.add(path);
    }
    return result;
  }

  static bool _isMentionBoundary(String character) =>
      RegExp(r'[\s(\[]').hasMatch(character);

  static int _matchScore(String path, String query) {
    if (query.isEmpty) return 3;
    final lower = path.toLowerCase();
    if (lower == query) return 0;
    if (lower.startsWith(query)) return 1;
    final name = lower.split('/').last;
    if (name.startsWith(query)) return 2;
    return 3;
  }

  static String _formatBytes(int bytes) =>
      bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(0)} KiB';
}

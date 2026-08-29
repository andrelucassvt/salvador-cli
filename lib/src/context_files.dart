import 'dart:convert';
import 'dart:io';

import 'file_mentions.dart';

class SkillInfo {
  const SkillInfo({required this.name, required this.description});

  final String name;
  final String description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillInfo &&
          name == other.name &&
          description == other.description;

  @override
  int get hashCode => Object.hash(name, description);
}

/// Descobre skills do projeto e le seus arquivos de contexto com o mesmo
/// confinamento por symlink usado pelas mencoes de arquivo.
class ContextFilesService {
  ContextFilesService(Directory root, {this.maxFileBytes = 64 * 1024})
    : root = root.absolute;

  final Directory root;
  final int maxFileBytes;
  List<SkillInfo>? _cachedSkills;

  List<SkillInfo> discoverSkills() {
    return List.unmodifiable(_cachedSkills ??= _readSkills());
  }

  String? agentsMdContext() {
    final file = _safeFile('AGENTS.md');
    if (file == null) return null;
    final content = _readText(file, truncate: false);
    if (content == null) return null;
    return '\nContexto do projeto (AGENTS.md):\n$content';
  }

  MentionExpansion expand(String input) {
    final names = _mentionedSkills(input);
    if (names.isEmpty) return MentionExpansion(prompt: input);

    final included = <String>[];
    final warnings = <String>[];
    final context = StringBuffer();
    for (final name in names) {
      final content = skillContent(name);
      if (content == null) {
        warnings.add('/$name ignorada: skill nao encontrada.');
        continue;
      }
      included.add(name);
      context
        ..writeln('\n--- skill mencionada: $name ---')
        ..writeln(content)
        ..writeln('--- fim da skill: $name ---');
    }

    if (included.isEmpty) {
      return MentionExpansion(prompt: input, warnings: warnings);
    }
    return MentionExpansion(
      prompt:
          '$input\n\nUse o conteudo abaixo como contexto das skills '
          'mencionadas pelo usuario.${context.toString()}',
      files: List.unmodifiable(included),
      warnings: List.unmodifiable(warnings),
    );
  }

  String? skillContent(String name) {
    if (!discoverSkills().any((skill) => skill.name == name)) return null;
    final file = _safeFile('.agents/skills/$name/SKILL.md');
    if (file == null) return null;
    return _readText(file, truncate: true);
  }

  List<SkillInfo> _readSkills() {
    final skillsDirectory = Directory('${root.path}/.agents/skills');
    if (!skillsDirectory.existsSync()) return const [];

    final skills = <SkillInfo>[];
    try {
      for (final entry in skillsDirectory.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = entry.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        final skillFile = _safeFile('.agents/skills/$name/SKILL.md');
        if (skillFile == null) continue;
        final content = _readText(skillFile, truncate: true);
        if (content == null) continue;
        skills.add(SkillInfo(name: name, description: _description(content)));
      }
    } on FileSystemException {
      return const [];
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  String? _readText(File file, {required bool truncate}) {
    try {
      final size = file.lengthSync();
      if (!truncate && size > maxFileBytes) return null;
      final bytes = file.readAsBytesSync();
      if (bytes.contains(0)) return null;
      final content = utf8.decode(bytes);
      if (!truncate || size <= maxFileBytes) return content;
      return '${content.substring(0, maxFileBytes.clamp(0, content.length))}'
          '\n[TRUNCADO]';
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
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

  static String _description(String content) {
    if (!content.startsWith('---')) return '';
    final closing = content.indexOf('\n---', 3);
    if (closing < 0) return '';
    final frontmatter = content.substring(3, closing);
    final match = RegExp(
      r'^description:\s*(.+)\s*$',
      multiLine: true,
    ).firstMatch(frontmatter);
    if (match == null) return '';
    final value = match.group(1)!.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static List<String> _mentionedSkills(String input) {
    final names = <String>[];
    final seen = <String>{};
    final pattern = RegExp(r'(?:^|\s)/([A-Za-z0-9_-]+)(?=\s|$)');
    for (final match in pattern.allMatches(input)) {
      final name = match.group(1)!;
      if (seen.add(name)) names.add(name);
    }
    return names;
  }
}

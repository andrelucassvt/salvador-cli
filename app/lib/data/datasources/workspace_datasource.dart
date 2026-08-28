import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';

/// Encapsula `FileMentionService`/`ToolRegistry` (pacote `salvador_cli`) e a
/// indexacao da arvore de arquivos do workspace. Mantem o indice em cache
/// por raiz, reconstruindo so quando a raiz muda - reindexar a cada tecla
/// digitada no composer seria uma regressao de performance.
class WorkspaceDataSource {
  Directory? _cachedRoot;
  FileMentionService? _mentions;
  ToolRegistry? _readOnlyTools;

  List<WorkspaceTreeEntryEntity> listTree(Directory root) {
    _ensureContext(root);
    final entries = <WorkspaceTreeEntryEntity>[];
    _visitDirectory(root, '', 0, entries);
    return entries;
  }

  Future<String> readFile(Directory root, String path) {
    _ensureContext(root);
    return _readOnlyTools!.execute(
      ToolCall(name: 'read_file', arguments: {'path': path}),
    );
  }

  List<String> fileSuggestions(
    Directory root,
    String input,
    int cursor, {
    int limit = 6,
  }) {
    _ensureContext(root);
    final active = _mentions!.activeMention(input, cursor);
    if (active == null) return const [];
    return _mentions!.suggest(active.query, limit: limit);
  }

  String insertMention(
    Directory root,
    String input,
    int cursor,
    String path,
  ) {
    _ensureContext(root);
    final active = _mentions!.activeMention(input, cursor);
    if (active == null) return input;
    final encoded = path.contains(' ') ? '@"$path"' : '@$path';
    return input.replaceRange(active.start, cursor, '$encoded ');
  }

  void _ensureContext(Directory root) {
    if (_cachedRoot?.path == root.path) return;
    _cachedRoot = root;
    _mentions = FileMentionService(root)..refresh();
    _readOnlyTools = ToolRegistry(root, permissions: AgentPermissions.readOnly);
  }

  void _visitDirectory(
    Directory directory,
    String prefix,
    int depth,
    List<WorkspaceTreeEntryEntity> entries,
  ) {
    final List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    children.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return _entityName(a).toLowerCase().compareTo(_entityName(b).toLowerCase());
    });

    for (final child in children) {
      final name = _entityName(child);
      final relative = prefix.isEmpty ? name : '$prefix/$name';
      if (child is Directory) {
        if (FileMentionService.ignoredDirectories.contains(name)) continue;
        entries.add(
          WorkspaceTreeEntryEntity(path: relative, depth: depth, isDirectory: true),
        );
        _visitDirectory(child, relative, depth + 1, entries);
      } else if (child is File) {
        var size = 0;
        try {
          size = child.lengthSync();
        } on FileSystemException {
          size = 0;
        }
        entries.add(
          WorkspaceTreeEntryEntity(
            path: relative,
            depth: depth,
            isDirectory: false,
            sizeBytes: size,
          ),
        );
      }
    }
  }

  static String _entityName(FileSystemEntity entity) =>
      entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
}

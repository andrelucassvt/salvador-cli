import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';
import 'package:salvador_desktop/domain/interfaces/workspace_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_state.dart';

class FileExplorerCubit extends Cubit<FileExplorerState> {
  FileExplorerCubit(this._repository) : super(const FileExplorerLoaded());

  final WorkspaceRepository _repository;

  Directory? _root;
  final Map<String, WorkspaceTreeEntryEntity> _entriesByPath = {};
  final List<WorkspaceTreeEntryEntity> _entriesInOrder = [];
  String _fileFilter = '';
  String? _selectedPath;

  Future<void> setRoot(Directory root) async {
    _root = root;
    _entriesByPath.clear();
    _entriesInOrder.clear();
    _fileFilter = '';
    _selectedPath = null;

    final result = await _repository.listTree(root: root);
    switch (result) {
      case Ok(:final value):
        for (final entry in value) {
          _entriesByPath[entry.path] = entry;
          _entriesInOrder.add(entry);
        }
      case Error():
        break;
    }
    emit(FileExplorerLoaded(treeEntries: _visibleEntries()));
  }

  void toggleDirectory(String path) {
    final entry = _entriesByPath[path];
    if (entry == null || !entry.isDirectory) return;
    final updated = entry.copyWith(expanded: !entry.expanded);
    _entriesByPath[path] = updated;
    final index = _entriesInOrder.indexWhere(
      (candidate) => candidate.path == path,
    );
    if (index >= 0) _entriesInOrder[index] = updated;
    emit((state as FileExplorerLoaded).copyWith(treeEntries: _visibleEntries()));
  }

  void setFileFilter(String query) {
    if (_fileFilter == query) return;
    _fileFilter = query;
    emit(
      (state as FileExplorerLoaded).copyWith(
        treeEntries: _visibleEntries(),
        fileFilter: _fileFilter,
      ),
    );
  }

  Future<void> openPreview(String path) async {
    final root = _root;
    if (root == null) return;
    final result = await _repository.readFile(root: root, path: path);
    switch (result) {
      case Error(:final error):
        _selectedPath = null;
        emit(
          (state as FileExplorerLoaded).copyWith(
            clearPreview: true,
            previewError: error.message,
            treeEntries: _visibleEntries(),
          ),
        );
      case Ok(:final value):
        _selectedPath = path;
        emit(
          (state as FileExplorerLoaded).copyWith(
            preview: value,
            clearPreviewError: true,
            treeEntries: _visibleEntries(),
          ),
        );
    }
  }

  void closePreview() {
    _selectedPath = null;
    emit(
      (state as FileExplorerLoaded).copyWith(
        clearPreview: true,
        clearPreviewError: true,
        treeEntries: _visibleEntries(),
      ),
    );
  }

  List<String> fileSuggestions(String input, int cursor, {int limit = 6}) {
    final root = _root;
    if (root == null) return const [];
    return _repository.fileSuggestions(
      root: root,
      input: input,
      cursor: cursor,
      limit: limit,
    );
  }

  String insertMention(String input, int cursor, String path) {
    final root = _root;
    if (root == null) return input;
    return _repository.insertMention(
      root: root,
      input: input,
      cursor: cursor,
      path: path,
    );
  }

  /// Insere a mencao do arquivo em preview na posicao do cursor, reutilizando
  /// a codificacao com aspas para caminhos com espaco.
  String mentionPreviewedFile(String input, int cursor) {
    final path = (state as FileExplorerLoaded).preview?.path;
    if (path == null) return input;
    final safeCursor = cursor.clamp(0, input.length);
    final encoded = path.contains(' ') ? '@"$path"' : '@$path';
    final needsSpace =
        safeCursor > 0 &&
        input[safeCursor - 1] != ' ' &&
        safeCursor < input.length;
    final mention = '$encoded ';
    return input.substring(0, safeCursor) +
        (needsSpace ? ' ' : '') +
        mention +
        input.substring(safeCursor);
  }

  List<WorkspaceTreeEntryEntity> _visibleEntries() {
    final filter = _fileFilter.toLowerCase();
    final matchCache = <String, bool>{};
    for (final entry in _entriesInOrder.reversed) {
      if (entry.isDirectory) {
        final selfMatch = entry.path.toLowerCase().contains(filter);
        final childMatch = _entriesInOrder.any(
          (candidate) =>
              candidate != entry &&
              candidate.path.startsWith('${entry.path}/') &&
              (matchCache[candidate.path] ?? false),
        );
        matchCache[entry.path] = filter.isEmpty || selfMatch || childMatch;
      } else {
        matchCache[entry.path] =
            filter.isEmpty || entry.path.toLowerCase().contains(filter);
      }
    }

    final visible = <WorkspaceTreeEntryEntity>[];
    final expandedPaths = <String>{};
    for (final entry in _entriesInOrder) {
      final parentPath = _parentPath(entry.path);
      if (filter.isEmpty &&
          entry.depth > 0 &&
          !expandedPaths.contains(parentPath)) {
        continue;
      }
      if (!(matchCache[entry.path] ?? true)) continue;
      visible.add(
        _selectedPath == entry.path ? entry.copyWith(selected: true) : entry,
      );
      if (entry.isDirectory && entry.expanded) expandedPaths.add(entry.path);
    }
    return List.unmodifiable(visible);
  }

  static String? _parentPath(String path) {
    final slash = path.lastIndexOf('/');
    if (slash < 0) return null;
    return path.substring(0, slash);
  }
}

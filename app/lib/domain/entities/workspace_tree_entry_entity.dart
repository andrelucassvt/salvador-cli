import 'package:flutter/foundation.dart';

/// Entrada imutavel da arvore de arquivos do workspace.
@immutable
class WorkspaceTreeEntryEntity {
  const WorkspaceTreeEntryEntity({
    required this.path,
    required this.depth,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.expanded = false,
    this.selected = false,
  });

  final String path;
  final int depth;
  final bool isDirectory;
  final int sizeBytes;
  final bool expanded;
  final bool selected;

  WorkspaceTreeEntryEntity copyWith({bool? expanded, bool? selected}) =>
      WorkspaceTreeEntryEntity(
        path: path,
        depth: depth,
        isDirectory: isDirectory,
        sizeBytes: sizeBytes,
        expanded: expanded ?? this.expanded,
        selected: selected ?? this.selected,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTreeEntryEntity &&
          path == other.path &&
          depth == other.depth &&
          isDirectory == other.isDirectory &&
          sizeBytes == other.sizeBytes &&
          expanded == other.expanded &&
          selected == other.selected;

  @override
  int get hashCode =>
      Object.hash(path, depth, isDirectory, sizeBytes, expanded, selected);

  @override
  String toString() =>
      'WorkspaceTreeEntryEntity(path: $path, depth: $depth, '
      'isDirectory: $isDirectory, expanded: $expanded, selected: $selected)';
}

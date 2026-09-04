import 'package:flutter/foundation.dart';
import 'package:salvador_desktop/domain/entities/file_preview_entity.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';

/// Estado unico: `setRoot` sempre roda antes de qualquer render, entao nao
/// ha diferenca util entre um estado "Initial" e uma arvore vazia.
@immutable
sealed class FileExplorerState {
  const FileExplorerState();

  @override
  String toString();
}

class FileExplorerLoaded extends FileExplorerState {
  const FileExplorerLoaded({
    this.treeEntries = const [],
    this.fileFilter = '',
    this.preview,
    this.previewError,
  });

  final List<WorkspaceTreeEntryEntity> treeEntries;
  final String fileFilter;
  final FilePreviewEntity? preview;
  final String? previewError;

  FileExplorerLoaded copyWith({
    List<WorkspaceTreeEntryEntity>? treeEntries,
    String? fileFilter,
    FilePreviewEntity? preview,
    bool clearPreview = false,
    String? previewError,
    bool clearPreviewError = false,
  }) {
    return FileExplorerLoaded(
      treeEntries: treeEntries ?? this.treeEntries,
      fileFilter: fileFilter ?? this.fileFilter,
      preview: clearPreview ? null : (preview ?? this.preview),
      previewError: clearPreviewError
          ? null
          : (previewError ?? this.previewError),
    );
  }

  @override
  String toString() =>
      'FileExplorerLoaded(treeEntries: ${treeEntries.length}, '
      'fileFilter: $fileFilter, preview: ${preview?.path}, '
      'previewError: $previewError)';
}

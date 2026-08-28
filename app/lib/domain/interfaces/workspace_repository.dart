import 'dart:io';

import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/file_preview_entity.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';

abstract class WorkspaceRepository {
  Future<Result<List<WorkspaceTreeEntryEntity>>> listTree({
    required Directory root,
  });

  Future<Result<FilePreviewEntity>> readFile({
    required Directory root,
    required String path,
  });

  /// Sincronos: nao fazem I/O, apenas consultam o indice de menções em
  /// memoria (ja construido por `listTree`/troca de raiz).
  List<String> fileSuggestions({
    required Directory root,
    required String input,
    required int cursor,
    int limit = 6,
  });

  String insertMention({
    required Directory root,
    required String input,
    required int cursor,
    required String path,
  });
}

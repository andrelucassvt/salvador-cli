import 'dart:io';

import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/file_preview_entity.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';
import 'package:salvador_desktop/domain/interfaces/workspace_repository.dart';

class FakeWorkspaceRepository implements WorkspaceRepository {
  List<WorkspaceTreeEntryEntity> tree = const [];
  AppException? readFileFailure;
  FilePreviewEntity? previewToReturn;
  List<String> suggestionsToReturn = const [];
  String insertMentionResult = '';
  int listTreeCallCount = 0;

  @override
  Future<Result<List<WorkspaceTreeEntryEntity>>> listTree({
    required Directory root,
  }) async {
    listTreeCallCount++;
    return Result.ok(tree);
  }

  @override
  Future<Result<FilePreviewEntity>> readFile({
    required Directory root,
    required String path,
  }) async {
    if (readFileFailure != null) return Result.error(readFileFailure!);
    return Result.ok(
      previewToReturn ??
          FilePreviewEntity(
            path: path,
            content: 'conteudo',
            lineCount: 1,
            sizeBytes: 8,
            language: 'texto',
          ),
    );
  }

  @override
  List<String> fileSuggestions({
    required Directory root,
    required String input,
    required int cursor,
    int limit = 6,
  }) => suggestionsToReturn;

  @override
  String insertMention({
    required Directory root,
    required String input,
    required int cursor,
    required String path,
  }) => insertMentionResult;
}

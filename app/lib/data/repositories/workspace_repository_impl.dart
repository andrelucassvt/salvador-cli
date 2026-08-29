import 'dart:convert';
import 'dart:io';

import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/data/datasources/workspace_datasource.dart';
import 'package:salvador_desktop/domain/entities/file_preview_entity.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';
import 'package:salvador_desktop/domain/interfaces/workspace_repository.dart';

class WorkspaceRepositoryImpl implements WorkspaceRepository {
  const WorkspaceRepositoryImpl(this._dataSource);

  final WorkspaceDataSource _dataSource;

  static const _languages = {
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'css': 'css',
    'dart': 'dart',
    'go': 'go',
    'html': 'html',
    'java': 'java',
    'js': 'javascript',
    'json': 'json',
    'kt': 'kotlin',
    'md': 'markdown',
    'py': 'python',
    'rs': 'rust',
    'sh': 'shell',
    'swift': 'swift',
    'ts': 'typescript',
    'txt': 'texto',
    'yaml': 'yaml',
    'yml': 'yaml',
  };

  @override
  Future<Result<List<WorkspaceTreeEntryEntity>>> listTree({
    required Directory root,
  }) async {
    try {
      return Result.ok(_dataSource.listTree(root));
    } catch (error, stackTrace) {
      return Result.error(
        UnknownException(
          'Falha inesperada',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<FilePreviewEntity>> readFile({
    required Directory root,
    required String path,
  }) async {
    try {
      final content = await _dataSource.readFile(root, path);
      if (content.startsWith('ERRO:')) {
        return Result.error(FileSystemFailureException(content));
      }
      return Result.ok(
        FilePreviewEntity(
          path: path,
          content: content,
          lineCount: content.split('\n').length,
          sizeBytes: utf8.encode(content).length,
          language: _languageFor(path),
        ),
      );
    } catch (error, stackTrace) {
      return Result.error(
        UnknownException(
          'Falha inesperada',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  List<String> fileSuggestions({
    required Directory root,
    required String input,
    required int cursor,
    int limit = 6,
  }) => _dataSource.fileSuggestions(root, input, cursor, limit: limit);

  @override
  String insertMention({
    required Directory root,
    required String input,
    required int cursor,
    required String path,
  }) => _dataSource.insertMention(root, input, cursor, path);

  @override
  List<String> skillSuggestions({
    required Directory root,
    required String input,
    required int cursor,
    int limit = 6,
  }) => _dataSource.skillSuggestions(root, input, cursor, limit: limit);

  @override
  String insertSkill({
    required Directory root,
    required String input,
    required int cursor,
    required String name,
  }) => _dataSource.insertSkill(root, input, cursor, name);

  static String _languageFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'texto';
    final extension = path.substring(dot + 1).toLowerCase();
    return _languages[extension] ?? extension;
  }
}

import 'dart:io';

import 'package:salvador_desktop/data/datasources/workspace_datasource.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';

class FakeWorkspaceDataSource implements WorkspaceDataSource {
  List<WorkspaceTreeEntryEntity> tree = const [];
  String readFileResult = 'conteudo';
  List<String> suggestions = const [];
  String insertMentionResult = '';

  @override
  List<WorkspaceTreeEntryEntity> listTree(Directory root) => tree;

  @override
  Future<String> readFile(Directory root, String path) async => readFileResult;

  @override
  List<String> fileSuggestions(
    Directory root,
    String input,
    int cursor, {
    int limit = 6,
  }) => suggestions;

  @override
  String insertMention(
    Directory root,
    String input,
    int cursor,
    String path,
  ) => insertMentionResult;
}

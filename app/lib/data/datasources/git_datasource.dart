import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';

/// Adapta `GitClient` (pacote `salvador_cli`) a raiz ativa do workspace.
class GitDataSource {
  GitDataSource({GitClient? client}) : _client = client ?? GitClient();

  final GitClient _client;

  Future<GitSnapshot> loadSnapshot(
    Directory root, {
    int maxCommits = GitClient.maxCommitsDefault,
  }) => _client.loadSnapshot(root, maxCommits: maxCommits);

  Future<GitCommitPage> loadMoreCommits(
    Directory root, {
    required int skip,
    required int count,
  }) => _client.loadMoreCommits(root, skip: skip, count: count);
}

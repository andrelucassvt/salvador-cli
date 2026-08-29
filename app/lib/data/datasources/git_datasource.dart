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
}

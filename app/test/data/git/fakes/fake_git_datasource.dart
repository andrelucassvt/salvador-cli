import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/git_datasource.dart';

GitSnapshot _emptySnapshot() => GitSnapshot(
  repository: const GitRepositoryState(
    kind: GitRepositoryKind.notRepository,
  ),
);

class FakeGitDataSource implements GitDataSource {
  GitSnapshot? snapshotToReturn;
  Object? errorToThrow;
  final List<int> requestedMaxCommits = [];

  @override
  Future<GitSnapshot> loadSnapshot(
    Directory root, {
    int maxCommits = GitClient.maxCommitsDefault,
  }) async {
    requestedMaxCommits.add(maxCommits);
    if (errorToThrow != null) throw errorToThrow!;
    return snapshotToReturn ?? _emptySnapshot();
  }
}

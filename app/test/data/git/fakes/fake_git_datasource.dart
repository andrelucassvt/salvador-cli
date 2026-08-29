import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/git_datasource.dart';

GitSnapshot _emptySnapshot() => GitSnapshot(
  repository: const GitRepositoryState(kind: GitRepositoryKind.notRepository),
);

class FakeGitDataSource implements GitDataSource {
  GitSnapshot? snapshotToReturn;
  Object? errorToThrow;
  GitCommitPage? pageToReturn;
  String? actionResult;
  final List<int> requestedMaxCommits = [];
  final List<(int, int)> requestedPages = [];
  final List<GitActionProposal> executedActions = [];

  @override
  Future<GitSnapshot> loadSnapshot(
    Directory root, {
    int maxCommits = GitClient.maxCommitsDefault,
  }) async {
    requestedMaxCommits.add(maxCommits);
    if (errorToThrow != null) throw errorToThrow!;
    return snapshotToReturn ?? _emptySnapshot();
  }

  @override
  Future<GitCommitPage> loadMoreCommits(
    Directory root, {
    required int skip,
    required int count,
  }) async {
    requestedPages.add((skip, count));
    if (errorToThrow != null) throw errorToThrow!;
    return pageToReturn ?? const GitCommitPage(commits: [], hasMore: false);
  }

  @override
  Future<String> executeAction(
    Directory root,
    GitActionProposal proposal,
  ) async {
    executedActions.add(proposal);
    if (errorToThrow != null) throw errorToThrow!;
    return actionResult ?? 'OK: acao executada';
  }
}

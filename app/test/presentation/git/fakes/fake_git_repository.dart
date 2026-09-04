import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';

class FakeGitRepository implements GitRepository {
  int loadCallCount = 0;
  Result<GitSnapshot>? nextResult;
  GitCommitPage? nextPage;
  Result<String>? nextActionResult;
  final List<GitActionProposal> executedActions = [];
  final List<Completer<Result<GitSnapshot>>> pending = [];

  @override
  Future<Result<GitSnapshot>> loadSnapshot({
    required Directory root,
    int maxCommits = GitClient.maxCommitsDefault,
  }) {
    loadCallCount++;
    final completer = Completer<Result<GitSnapshot>>();
    pending.add(completer);
    final queued = nextResult;
    if (queued != null) {
      nextResult = null;
      completer.complete(queued);
    }
    return completer.future;
  }

  @override
  Future<Result<GitCommitPage>> loadMoreCommits({
    required Directory root,
    required int skip,
    required int count,
  }) async {
    final page = nextPage;
    nextPage = null;
    if (page == null) {
      return const Result.ok(GitCommitPage(commits: [], hasMore: false));
    }
    return Result.ok(page);
  }

  @override
  Future<Result<String>> executeAction({
    required Directory root,
    required GitActionProposal proposal,
  }) async {
    executedActions.add(proposal);
    final queued = nextActionResult;
    nextActionResult = null;
    if (queued != null) return queued;
    return const Result.ok('OK: acao executada');
  }

  /// Completa a requisicao mais antiga pendente com [result], mantendo as
  /// demais abertas - usado para simular resultado atrasado da raiz antiga.
  void completeFirst(Result<GitSnapshot> result) {
    final completer = pending.removeAt(0);
    completer.complete(result);
  }

  /// Completa todas as requisicoes pendentes com [result].
  void completeAll(Result<GitSnapshot> result) {
    for (final completer in pending) {
      completer.complete(result);
    }
    pending.clear();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';

class FakeGitRepository implements GitRepository {
  int loadCallCount = 0;
  Result<GitSnapshot>? nextResult;
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

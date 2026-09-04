import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';

class GitCubit extends Cubit<GitState> {
  GitCubit(this._repository) : super(const GitEmpty());

  static const pageSize = 50;

  final GitRepository _repository;

  Directory? _root;
  int _requestToken = 0;

  /// Vincula a raiz ativa: carrega o snapshot, descartando respostas
  /// obsoletas de raizes anteriores.
  Future<void> setRoot(Directory? root) async {
    _root = root;
    final token = ++_requestToken;
    if (root == null) {
      emit(const GitEmpty());
      return;
    }
    final current = state;
    emit(GitLoading(previous: current is GitLoaded ? current : null));
    final result = await _repository.loadSnapshot(root: root);
    if (token != _requestToken) return;
    switch (result) {
      case Ok(:final value):
        final repository = value.repository;
        if (repository.kind == GitRepositoryKind.notRepository) {
          emit(const GitNotRepository());
        } else if (repository.kind == GitRepositoryKind.repositoryOutsideRoot) {
          emit(GitRepositoryOutsideRoot(topLevel: repository.topLevel));
        } else {
          final previous = state is GitLoading
              ? (state as GitLoading).previous
              : null;
          emit(
            GitLoaded(
              snapshot: value,
              searchQuery: previous?.searchQuery ?? '',
              selectedRef: _refSurvives(previous?.selectedRef, value)
                  ? previous?.selectedRef
                  : null,
              selectedCommitHash:
                  _commitSurvives(previous?.selectedCommitHash, value)
                  ? previous?.selectedCommitHash
                  : null,
              selectedFilePath: _fileSurvives(previous?.selectedFilePath, value)
                  ? previous?.selectedFilePath
                  : null,
            ),
          );
        }
      case Error(:final error):
        emit(GitFailure(message: error.message));
    }
  }

  Future<void> refresh() async {
    final root = _root;
    if (root == null) return;
    await setRoot(root);
  }

  /// Filtra branches, tags e worktree de forma case-insensitive.
  void search(String query) {
    final current = state;
    if (current is! GitLoaded || current.searchQuery == query) return;
    emit(current.copyWith(searchQuery: query));
  }

  void selectCommit(String hash) {
    final current = state;
    if (current is! GitLoaded) return;
    emit(current.copyWith(selectedCommitHash: hash));
  }

  void selectRef(String refName) {
    final current = state;
    if (current is! GitLoaded) return;
    emit(current.copyWith(selectedRef: refName));
  }

  void selectFile(String path) {
    final current = state;
    if (current is! GitLoaded) return;
    emit(current.copyWith(selectedFilePath: path));
  }

  /// Troca apenas para uma branch local presente no snapshot atual. A execucao
  /// continua centralizada em [executeApproved], com refresh apos sucesso.
  Future<bool> checkoutBranch(String branch) {
    final current = state;
    if (current is! GitLoaded ||
        current.snapshot.repository.branch == branch ||
        !current.snapshot.localBranches.any((ref) => ref.shortName == branch)) {
      return Future.value(false);
    }
    return executeApproved(
      GitActionProposal(type: GitActionType.checkoutBranch, refName: branch),
    );
  }

  /// Descarta o erro da ultima acao aprovada.
  void clearActionError() {
    final current = state;
    if (current is! GitLoaded || current.actionError == null) return;
    emit(current.copyWith(clearActionError: true));
  }

  /// Carrega a proxima pagina do historico, concatenando sem duplicar
  /// hashes e preservando a selecao atual.
  Future<void> loadMore() async {
    final current = state;
    final root = _root;
    if (current is! GitLoaded || root == null || current.loadingMore) {
      return;
    }
    final knownHashes = {
      for (final commit in current.visibleCommits) commit.hash,
    };
    emit(current.copyWith(loadingMore: true));
    final result = await _repository.loadMoreCommits(
      root: root,
      skip: current.visibleCommits.length,
      count: pageSize,
    );
    final latest = state;
    if (latest is! GitLoaded) return;
    switch (result) {
      case Ok(:final value):
        final page = value;
        final appended = [
          for (final commit in page.commits)
            if (!knownHashes.contains(commit.hash)) commit,
        ];
        emit(
          latest.copyWith(
            commits: [...latest.visibleCommits, ...appended],
            hasMoreCommits: page.hasMore,
            loadingMore: false,
          ),
        );
      case Error():
        emit(latest.copyWith(loadingMore: false));
    }
  }

  static bool _refSurvives(String? refName, GitSnapshot snapshot) {
    if (refName == null) return false;
    for (final ref in [
      ...snapshot.localBranches,
      ...snapshot.remoteBranches,
      ...snapshot.tags,
    ]) {
      if (ref.name == refName) return true;
    }
    return false;
  }

  static bool _commitSurvives(String? hash, GitSnapshot snapshot) {
    if (hash == null) return false;
    for (final commit in snapshot.commits) {
      if (commit.hash == hash) return true;
    }
    return false;
  }

  static bool _fileSurvives(String? path, GitSnapshot snapshot) {
    if (path == null) return false;
    for (final entry in snapshot.worktree) {
      if (entry.path == path) return true;
    }
    return false;
  }

  /// Executa uma acao aprovada pela interface, recarregando o snapshot
  /// somente apos sucesso. Falha preserva o snapshot anterior e expoe o erro.
  Future<bool> executeApproved(GitActionProposal proposal) async {
    final current = state;
    final root = _root;
    if (current is! GitLoaded ||
        root == null ||
        current.executingAction != null ||
        current.loadingMore) {
      return false;
    }
    emit(current.copyWith(executingAction: proposal, clearActionError: true));
    final result = await _repository.executeAction(
      root: root,
      proposal: proposal,
    );
    final latest = state;
    if (latest is! GitLoaded) return false;
    switch (result) {
      case Ok():
        emit(latest.copyWith(clearExecutingAction: true));
        await refresh();
        return true;
      case Error(:final error):
        emit(
          latest.copyWith(
            clearExecutingAction: true,
            actionError: error.message,
          ),
        );
        return false;
    }
  }
}

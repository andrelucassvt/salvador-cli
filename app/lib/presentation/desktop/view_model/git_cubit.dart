import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';

class GitCubit extends Cubit<GitState> {
  GitCubit(this._repository) : super(const GitEmpty());

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
    emit(
      GitLoading(
        previous: current is GitLoaded ? current.snapshot : null,
      ),
    );
    final result = await _repository.loadSnapshot(root: root);
    if (token != _requestToken) return;
    switch (result) {
      case Ok(:final value):
        final repository = value.repository;
        if (repository.kind == GitRepositoryKind.notRepository) {
          emit(const GitNotRepository());
        } else if (repository.kind ==
            GitRepositoryKind.repositoryOutsideRoot) {
          emit(GitRepositoryOutsideRoot(topLevel: repository.topLevel));
        } else {
          emit(GitLoaded(snapshot: value));
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
}

import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/data/datasources/git_datasource.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';

class GitRepositoryImpl implements GitRepository {
  const GitRepositoryImpl(this._dataSource);

  final GitDataSource _dataSource;

  @override
  Future<Result<GitSnapshot>> loadSnapshot({
    required Directory root,
    int maxCommits = GitClient.maxCommitsDefault,
  }) async {
    try {
      final snapshot = await _dataSource.loadSnapshot(
        root,
        maxCommits: maxCommits,
      );
      return Result.ok(snapshot);
    } on GitException catch (error) {
      return Result.error(
        GitFailureException(error.message, cause: error.cause),
      );
    } on ProcessException catch (error, stackTrace) {
      return Result.error(
        GitFailureException(
          'Falha ao executar git: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
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
  Future<Result<GitCommitPage>> loadMoreCommits({
    required Directory root,
    required int skip,
    required int count,
  }) async {
    try {
      final page = await _dataSource.loadMoreCommits(
        root,
        skip: skip,
        count: count,
      );
      return Result.ok(page);
    } on GitException catch (error) {
      return Result.error(
        GitFailureException(error.message, cause: error.cause),
      );
    } on ProcessException catch (error, stackTrace) {
      return Result.error(
        GitFailureException(
          'Falha ao executar git: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
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
  Future<Result<String>> executeAction({
    required Directory root,
    required GitActionProposal proposal,
  }) async {
    try {
      final output = await _dataSource.executeAction(root, proposal);
      return Result.ok(output);
    } on GitException catch (error) {
      return Result.error(
        GitFailureException(error.message, cause: error.cause),
      );
    } on ProcessException catch (error, stackTrace) {
      return Result.error(
        GitFailureException(
          'Falha ao executar git: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
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
}

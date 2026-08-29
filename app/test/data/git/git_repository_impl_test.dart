import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/data/repositories/git_repository_impl.dart';

import 'fakes/fake_git_datasource.dart';

void main() {
  late FakeGitDataSource fakeDataSource;
  late GitRepositoryImpl repository;
  final root = Directory.systemTemp;

  setUp(() {
    fakeDataSource = FakeGitDataSource();
    repository = GitRepositoryImpl(fakeDataSource);
  });

  GitSnapshot validSnapshot() => GitSnapshot(
    repository: const GitRepositoryState(
      kind: GitRepositoryKind.valid,
      topLevel: '/repo/raiz',
      branch: 'main',
      headOid: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
    ),
    ahead: 3,
    behind: 1,
    worktree: const [
      GitWorktreeEntry(path: 'a.txt', status: GitWorktreeStatus.unstaged),
    ],
  );

  group('GitRepositoryImpl.loadSnapshot', () {
    test('loadSnapshot_whenDataSourceSucceeds_returnsOkWithSnapshot', () async {
      final snapshot = validSnapshot();
      fakeDataSource.snapshotToReturn = snapshot;

      final result = await repository.loadSnapshot(root: root);

      result.when(
        ok: (value) => expect(value, same(snapshot)),
        error: (_) => fail('esperava sucesso'),
      );
    });

    test(
      'loadSnapshot_whenGitException_returnsGitFailureExceptionWithCause',
      () async {
        const cause = ProcessException('git', ['-C', '/repo/raiz']);
        fakeDataSource.errorToThrow = GitException(
          'repositorio corrompido',
          cause: cause,
        );

        final result = await repository.loadSnapshot(root: root);

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) {
            expect(error, isA<GitFailureException>());
            expect(error.message, 'repositorio corrompido');
            expect(error.cause, same(cause));
          },
        );
      },
    );

    test(
      'loadSnapshot_whenProcessException_returnsGitFailureException',
      () async {
        fakeDataSource.errorToThrow = const ProcessException('git', [
          '-C',
          '/repo/raiz',
        ], 'Exec format error');

        final result = await repository.loadSnapshot(root: root);

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) {
            expect(error, isA<GitFailureException>());
            expect(error.message, contains('Exec format error'));
            expect(error.cause, isA<ProcessException>());
          },
        );
      },
    );

    test('loadSnapshot_whenUnknownError_preservesCauseAndStackTrace', () async {
      final failure = StateError('inesperado');
      fakeDataSource.errorToThrow = failure;

      final result = await repository.loadSnapshot(root: root);

      result.when(
        ok: (_) => fail('esperava erro'),
        error: (error) {
          expect(error, isA<UnknownException>());
          expect(error.message, 'Falha inesperada');
          expect(error.cause, same(failure));
          expect(error.stackTrace, isNotNull);
        },
      );
    });

    test('loadSnapshot_forwardaMaxCommitsAoDatasource', () async {
      fakeDataSource.snapshotToReturn = validSnapshot();

      await repository.loadSnapshot(root: root, maxCommits: 5);

      expect(fakeDataSource.requestedMaxCommits, [5]);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';

import 'fakes/fake_git_repository.dart';

void main() {
  late FakeGitRepository fakeRepository;
  late Directory root;
  late Directory otherRoot;

  setUp(() {
    fakeRepository = FakeGitRepository();
    root = Directory('/repo/raiz');
    otherRoot = Directory('/repo/outra-raiz');
  });

  GitSnapshot validSnapshot({int ahead = 0, String branch = 'main'}) =>
      GitSnapshot(
        repository: GitRepositoryState(
          kind: GitRepositoryKind.valid,
          topLevel: '/repo/raiz',
          branch: branch,
          headOid: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
        ),
        ahead: ahead,
        worktree: const [
          GitWorktreeEntry(path: 'a.txt', status: GitWorktreeStatus.unstaged),
        ],
      );

  GitSnapshot notRepositorySnapshot() => const GitSnapshot(
    repository: GitRepositoryState(kind: GitRepositoryKind.notRepository),
  );

  GitSnapshot outsideRootSnapshot() => const GitSnapshot(
    repository: GitRepositoryState(
      kind: GitRepositoryKind.repositoryOutsideRoot,
      topLevel: '/repo',
    ),
  );

  group('GitCubit.setRoot', () {
    blocTest<GitCubit, GitState>(
      'setRoot_whenNull_emitsEmptySemConsultarRepositorio',
      build: () => GitCubit(fakeRepository),
      act: (cubit) => cubit.setRoot(null),
      expect: () => [isA<GitEmpty>()],
      verify: (_) => expect(fakeRepository.loadCallCount, 0),
    );

    blocTest<GitCubit, GitState>(
      'setRoot_whenValidRepository_emitsLoadingThenLoaded',
      build: () {
        fakeRepository.nextResult = Result.ok(validSnapshot());
        return GitCubit(fakeRepository);
      },
      act: (cubit) => cubit.setRoot(root),
      expect: () => [
        isA<GitLoading>()
            .having((s) => s.previous, 'previous', isNull),
        isA<GitLoaded>().having(
          (s) => s.snapshot.repository.branch,
          'branch',
          'main',
        ),
      ],
    );

    blocTest<GitCubit, GitState>(
      'setRoot_whenNotRepository_emitsGitNotRepository',
      build: () {
        fakeRepository.nextResult = Result.ok(notRepositorySnapshot());
        return GitCubit(fakeRepository);
      },
      act: (cubit) => cubit.setRoot(root),
      expect: () => [
        isA<GitLoading>(),
        isA<GitNotRepository>(),
      ],
    );

    blocTest<GitCubit, GitState>(
      'setRoot_whenOutsideRoot_emitsGitRepositoryOutsideRoot',
      build: () {
        fakeRepository.nextResult = Result.ok(outsideRootSnapshot());
        return GitCubit(fakeRepository);
      },
      act: (cubit) => cubit.setRoot(root),
      expect: () => [
        isA<GitLoading>(),
        isA<GitRepositoryOutsideRoot>().having(
          (s) => s.topLevel,
          'topLevel',
          '/repo',
        ),
      ],
    );

    blocTest<GitCubit, GitState>(
      'setRoot_whenRepositoryFails_emitsGitFailureApresentavel',
      build: () {
        fakeRepository.nextResult = const Result.error(
          GitFailureException('repositorio corrompido'),
        );
        return GitCubit(fakeRepository);
      },
      act: (cubit) => cubit.setRoot(root),
      expect: () => [
        isA<GitLoading>(),
        isA<GitFailure>()
            .having((s) => s.message, 'message', 'repositorio corrompido'),
      ],
    );
  });

  group('GitCubit.refresh', () {
    blocTest<GitCubit, GitState>(
      'refresh_quandoJaCarregado_preservaSnapshotAnteriorDuranteAtualizacao',
      build: () {
        fakeRepository.nextResult = Result.ok(validSnapshot(ahead: 1));
        return GitCubit(fakeRepository);
      },
      seed: () => GitLoaded(snapshot: validSnapshot(ahead: 1)),
      act: (cubit) async {
        await cubit.setRoot(root);
        fakeRepository.nextResult = Result.ok(validSnapshot(ahead: 4));
        await cubit.refresh();
      },
      expect: () => [
        isA<GitLoading>().having(
          (s) => s.previous?.ahead,
          'previous.ahead',
          1,
        ),
        isA<GitLoaded>().having((s) => s.snapshot.ahead, 'ahead', 1),
        isA<GitLoading>().having(
          (s) => s.previous?.ahead,
          'previous.ahead',
          1,
        ),
        isA<GitLoaded>().having((s) => s.snapshot.ahead, 'ahead', 4),
      ],
    );

    blocTest<GitCubit, GitState>(
      'refresh_semRaiz_naoConsultaRepositorio',
      build: () => GitCubit(fakeRepository),
      seed: () => const GitEmpty(),
      act: (cubit) => cubit.refresh(),
      expect: () => [],
      verify: (_) => expect(fakeRepository.loadCallCount, 0),
    );
  });

  group('GitCubit concorrencia', () {
    test('resultado atrasado da raiz antiga nao sobrescreve a raiz atual',
        () async {
      final cubit = GitCubit(fakeRepository);
      final snapshotA = validSnapshot(branch: 'main');
      final snapshotB = validSnapshot(branch: 'feature');

      unawaited(cubit.setRoot(root));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<GitLoading>());

      unawaited(cubit.setRoot(otherRoot));
      await Future<void>.delayed(Duration.zero);

      // Resposta atrasada da raiz antiga chega primeiro e deve ser descartada.
      fakeRepository.completeFirst(Result.ok(snapshotA));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<GitLoading>());

      fakeRepository.completeFirst(Result.ok(snapshotB));
      await Future<void>.delayed(Duration.zero);
      final loaded = cubit.state;
      expect(loaded, isA<GitLoaded>());
      expect((loaded as GitLoaded).snapshot.repository.branch, 'feature');

      await cubit.close();
    });
  });
}

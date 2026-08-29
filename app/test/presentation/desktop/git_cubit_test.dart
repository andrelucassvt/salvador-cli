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
        commits: [
          GitCommit(
            hash: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
            shortHash: '6b8dc2e',
            subject: 'commit principal',
            authorName: 't',
            authorEmail: 't@t.co',
            authorDate: DateTime(2026, 8, 29),
          ),
        ],
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
        isA<GitLoading>().having((s) => s.previous, 'previous', isNull),
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
      expect: () => [isA<GitLoading>(), isA<GitNotRepository>()],
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
        isA<GitFailure>().having(
          (s) => s.message,
          'message',
          'repositorio corrompido',
        ),
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
          (s) => s.previous?.snapshot.ahead,
          'previous.ahead',
          1,
        ),
        isA<GitLoaded>().having((s) => s.snapshot.ahead, 'ahead', 1),
        isA<GitLoading>().having(
          (s) => s.previous?.snapshot.ahead,
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
    test(
      'resultado atrasado da raiz antiga nao sobrescreve a raiz atual',
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
      },
    );
  });

  group('GitCubit selecao e filtro', () {
    GitLoaded loadedWith(GitSnapshot snapshot) => GitLoaded(snapshot: snapshot);

    test('selectCommit marca o commit selecionado', () async {
      final snapshot = validSnapshot();
      fakeRepository.nextResult = Result.ok(snapshot);
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);

      cubit.selectCommit('6b8dc2efa9f5ff3a00f6262229969f841cefa6fc');

      final state = cubit.state as GitLoaded;
      expect(
        state.selectedCommitHash,
        '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
      );
      await cubit.close();
    });

    test('selectRef e selectFile marcam as selecoes', () async {
      final snapshot = validSnapshot();
      fakeRepository.nextResult = Result.ok(snapshot);
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);

      cubit.selectRef('refs/heads/main');
      cubit.selectFile('a.txt');

      final state = cubit.state as GitLoaded;
      expect(state.selectedRef, 'refs/heads/main');
      expect(state.selectedFilePath, 'a.txt');
      await cubit.close();
    });

    blocTest<GitCubit, GitState>(
      'search filtra branches e worktree case-insensitive',
      build: () {
        final snapshot = GitSnapshot(
          repository: const GitRepositoryState(
            kind: GitRepositoryKind.valid,
            topLevel: '/repo/raiz',
            branch: 'main',
            headOid: '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
          ),
          localBranches: const [
            GitRef(name: 'refs/heads/main', hash: 'a'),
            GitRef(name: 'refs/heads/Feature-X', hash: 'b'),
          ],
          remoteBranches: const [
            GitRef(name: 'refs/remotes/origin/main', hash: 'a'),
          ],
          tags: const [GitRef(name: 'refs/tags/v1.0.0', hash: 'c')],
          worktree: const [
            GitWorktreeEntry(
              path: 'src/main.dart',
              status: GitWorktreeStatus.unstaged,
            ),
            GitWorktreeEntry(
              path: 'README.md',
              status: GitWorktreeStatus.untracked,
            ),
          ],
        );
        fakeRepository.nextResult = Result.ok(snapshot);
        return GitCubit(fakeRepository);
      },
      seed: () => loadedWith(
        GitSnapshot(
          repository: const GitRepositoryState(
            kind: GitRepositoryKind.valid,
            topLevel: '/repo/raiz',
            branch: 'main',
          ),
        ),
      ),
      act: (cubit) async {
        await cubit.setRoot(root);
        cubit.search('FEATURE');
      },
      expect: () => [
        isA<GitLoading>(),
        isA<GitLoaded>(),
        isA<GitLoaded>()
            .having((s) => s.searchQuery, 'searchQuery', 'FEATURE')
            .having(
              (s) => s.visibleLocalBranches.map((r) => r.shortName),
              'visibleLocalBranches',
              ['Feature-X'],
            )
            .having(
              (s) => s.visibleRemoteBranches,
              'visibleRemoteBranches',
              isEmpty,
            )
            .having((s) => s.visibleTags, 'visibleTags', isEmpty)
            .having((s) => s.visibleWorktree, 'visibleWorktree', isEmpty),
      ],
    );

    test(
      'limpa selecoes que nao existem mais no snapshot atualizado',
      () async {
        final firstSnapshot = validSnapshot();
        fakeRepository.nextResult = Result.ok(firstSnapshot);
        final cubit = GitCubit(fakeRepository);
        await cubit.setRoot(root);
        cubit.selectCommit('6b8dc2efa9f5ff3a00f6262229969f841cefa6fc');
        cubit.selectFile('a.txt');

        final withoutCommit = GitSnapshot(
          repository: const GitRepositoryState(
            kind: GitRepositoryKind.valid,
            topLevel: '/repo/raiz',
            branch: 'main',
            headOid: 'outrohash0000000000000000000000000000000000',
          ),
          worktree: const [
            GitWorktreeEntry(
              path: 'outro.txt',
              status: GitWorktreeStatus.untracked,
            ),
          ],
        );
        fakeRepository.nextResult = Result.ok(withoutCommit);
        await cubit.refresh();

        final state = cubit.state as GitLoaded;
        expect(state.selectedCommitHash, isNull);
        expect(state.selectedFilePath, isNull);
        expect(state.selectedRef, isNull);
        await cubit.close();
      },
    );
  });

  group('GitCubit paginacao', () {
    test('loadMore concatena sem duplicar e preserva a selecao', () async {
      final snapshot = GitSnapshot(
        repository: const GitRepositoryState(
          kind: GitRepositoryKind.valid,
          topLevel: '/repo/raiz',
          branch: 'main',
          headOid: 'a000000000000000000000000000000000000000',
        ),
        commits: [
          GitCommit(
            hash: 'a000000000000000000000000000000000000000',
            shortHash: 'a000000',
            subject: 'primeiro',
            authorName: 't',
            authorEmail: 't@t.co',
            authorDate: DateTime(2026, 8, 29),
          ),
        ],
      );
      fakeRepository.nextResult = Result.ok(snapshot);
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);
      cubit.selectCommit('a000000000000000000000000000000000000000');

      fakeRepository.nextPage = GitCommitPage(
        commits: [
          GitCommit(
            hash: 'b1111111111111111111111111111111111111111',
            shortHash: 'b111111',
            subject: 'segundo',
            authorName: 't',
            authorEmail: 't@t.co',
            authorDate: DateTime(2026, 8, 29),
          ),
          GitCommit(
            hash: 'c2222222222222222222222222222222222222222',
            shortHash: 'c222222',
            subject: 'terceiro',
            authorName: 't',
            authorEmail: 't@t.co',
            authorDate: DateTime(2026, 8, 29),
          ),
        ],
        hasMore: true,
      );
      await cubit.loadMore();

      final state = cubit.state as GitLoaded;
      expect(state.visibleCommits.map((c) => c.hash), [
        'a000000000000000000000000000000000000000',
        'b1111111111111111111111111111111111111111',
        'c2222222222222222222222222222222222222222',
      ]);
      expect(
        state.visibleCommits.map((c) => c.hash).toSet().length,
        state.visibleCommits.length,
        reason: 'hashes nao podem duplicar apos concatenar paginas',
      );
      expect(
        state.selectedCommitHash,
        'a000000000000000000000000000000000000000',
      );
      expect(state.hasMoreCommits, isTrue);
      await cubit.close();
    });
  });

  group('GitCubit.executeApproved', () {
    const proposal = GitActionProposal(
      type: GitActionType.stage,
      paths: ['a.txt'],
    );

    test(
      'confirma executa exatamente uma vez com a proposta exibida',
      () async {
        fakeRepository.nextResult = Result.ok(validSnapshot());
        final cubit = GitCubit(fakeRepository);
        await cubit.setRoot(root);

        fakeRepository.nextActionResult = const Result.ok('OK: staged');
        fakeRepository.nextResult = Result.ok(validSnapshot());
        final executed = await cubit.executeApproved(proposal);

        expect(executed, isTrue);
        expect(fakeRepository.executedActions, [proposal]);
        expect(
          (cubit.state as GitLoaded).actionError,
          isNull,
          reason: 'sucesso nao deixa erro',
        );
        await cubit.close();
      },
    );

    test('sucesso recarrega o snapshot (refresh) e preserva selecao', () async {
      fakeRepository.nextResult = Result.ok(validSnapshot());
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);
      cubit.selectCommit('6b8dc2efa9f5ff3a00f6262229969f841cefa6fc');
      final loadsBefore = fakeRepository.loadCallCount;

      fakeRepository.nextActionResult = const Result.ok('OK');
      fakeRepository.nextResult = Result.ok(validSnapshot());
      await cubit.executeApproved(proposal);

      expect(fakeRepository.loadCallCount, loadsBefore + 1);
      expect(
        (cubit.state as GitLoaded).selectedCommitHash,
        '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc',
      );
      await cubit.close();
    });

    test('falha preserva o snapshot anterior e expoe o erro', () async {
      final first = validSnapshot();
      fakeRepository.nextResult = Result.ok(first);
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);
      final loadsBefore = fakeRepository.loadCallCount;

      fakeRepository.nextActionResult = const Result.error(
        GitFailureException('conflito no merge'),
      );
      final executed = await cubit.executeApproved(proposal);

      expect(executed, isFalse);
      final state = cubit.state as GitLoaded;
      expect(state.snapshot, same(first));
      expect(state.actionError, 'conflito no merge');
      expect(
        fakeRepository.loadCallCount,
        loadsBefore,
        reason: 'sem refresh apos falha',
      );
      await cubit.close();
    });

    test('bloqueia execucao concorrente', () async {
      fakeRepository.nextResult = Result.ok(validSnapshot());
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);
      fakeRepository.nextActionResult = const Result.ok('OK');
      fakeRepository.nextResult = Result.ok(validSnapshot());

      final firstCall = cubit.executeApproved(proposal);
      final secondCall = cubit.executeApproved(proposal);

      expect(await secondCall, isFalse);
      expect(await firstCall, isTrue);
      expect(
        fakeRepository.executedActions,
        [proposal],
        reason: 'a segunda chamada concorrente nao executa nada',
      );
      await cubit.close();
    });

    test('cancelar nunca chama execute', () async {
      fakeRepository.nextResult = Result.ok(validSnapshot());
      final cubit = GitCubit(fakeRepository);
      await cubit.setRoot(root);

      fakeRepository.nextActionResult = const Result.ok('OK');
      fakeRepository.nextResult = Result.ok(validSnapshot());
      await cubit.executeApproved(proposal);

      expect(fakeRepository.executedActions, [proposal]);
      await cubit.close();
    });
  });
}

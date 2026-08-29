import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/presentation/desktop/content/git_workspace.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';

import 'fakes/fake_git_repository.dart';

void main() {
  late FakeGitRepository fakeRepository;
  late GitCubit cubit;
  final root = Directory('/repo/raiz');

  const headHash = 'a000000000000000000000000000000000000000';
  const middleHash = 'b1111111111111111111111111111111111111111';
  const baseHash = 'c2222222222222222222222222222222222222222';

  GitCommit commit(
    String hash,
    String subject, {
    List<String> parents = const [],
  }) => GitCommit(
    hash: hash,
    shortHash: hash.substring(0, 7),
    subject: subject,
    authorName: 'Test',
    authorEmail: 't@t.co',
    authorDate: DateTime(2026, 8, 29),
    parentHashes: parents,
    files: [GitCommitFile(status: 'M', path: 'lib/main.dart')],
  );

  GitSnapshot validSnapshot() => GitSnapshot(
    repository: const GitRepositoryState(
      kind: GitRepositoryKind.valid,
      topLevel: '/repo/raiz',
      branch: 'main',
      headOid: headHash,
    ),
    upstream: 'origin/main',
    ahead: 3,
    behind: 1,
    localBranches: const [
      GitRef(name: 'refs/heads/main', hash: headHash),
      GitRef(name: 'refs/heads/feature', hash: middleHash),
    ],
    remoteBranches: const [
      GitRef(name: 'refs/remotes/origin/main', hash: headHash),
    ],
    tags: const [GitRef(name: 'refs/tags/v1.0.0', hash: baseHash)],
    stashCount: 1,
    commits: [
      commit(headHash, 'merge da feature', parents: [middleHash, baseHash]),
      commit(middleHash, 'feat: unicode çãü'),
      commit(baseHash, 'commit base'),
    ],
    worktree: const [
      GitWorktreeEntry(path: 'lib/a.dart', status: GitWorktreeStatus.staged),
      GitWorktreeEntry(path: 'lib/b.dart', status: GitWorktreeStatus.unstaged),
      GitWorktreeEntry(path: 'novo.txt', status: GitWorktreeStatus.untracked),
      GitWorktreeEntry(
        path: 'conflito.txt',
        status: GitWorktreeStatus.conflicted,
      ),
    ],
  );

  setUp(() {
    fakeRepository = FakeGitRepository();
    cubit = GitCubit(fakeRepository);
  });

  tearDown(() async {
    await cubit.close();
  });

  Future<GitCubit> loadValid({GitSnapshot? snapshot}) async {
    fakeRepository.nextResult = Result.ok(snapshot ?? validSnapshot());
    await cubit.setRoot(root);
    return cubit;
  }

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required GitCubit target,
    Size size = const Size(1100, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<GitCubit>.value(
            value: target,
            child: const GitWorkspace(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('GitWorkspace valido', () {
    testWidgets('mostra resumo, grupos de refs, grafo e alteracoes', (
      tester,
    ) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      expect(find.byKey(const Key('git-branches-panel')), findsOneWidget);
      expect(find.text('Atual'), findsOneWidget);
      expect(find.text('Locais'), findsOneWidget);
      expect(find.text('Remotas'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Stashes'), findsOneWidget);

      expect(find.byKey(const Key('git-ref-refs/heads/main')), findsOneWidget);
      expect(
        find.byKey(const Key('git-ref-refs/heads/feature')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('git-ref-refs/remotes/origin/main')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('git-ref-refs/tags/v1.0.0')), findsOneWidget);
      expect(find.byKey(const Key('git-stash-0')), findsOneWidget);

      expect(find.byKey(const Key('git-commit-graph')), findsOneWidget);
      expect(find.byKey(const Key('git-commit-row-a000000')), findsOneWidget);

      expect(find.byKey(const Key('git-commit-inspector')), findsOneWidget);
      expect(
        find.text('merge da feature'),
        findsNWidgets(2),
        reason: 'linha do grafo e inspector exibem o mesmo commit',
      );

      expect(find.byKey(const Key('git-worktree-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('git-worktree-group-staged')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('git-worktree-group-unstaged')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('git-worktree-group-untracked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('git-worktree-group-conflicted')),
        findsOneWidget,
      );
    });

    testWidgets('pesquisa filtra refs e worktree case-insensitive', (
      tester,
    ) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.enterText(
        find.byKey(const Key('git-branch-search')),
        'FEATURE',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('git-ref-refs/heads/feature')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('git-ref-refs/heads/main')), findsNothing);
      expect(find.byKey(const Key('git-ref-refs/tags/v1.0.0')), findsNothing);
    });

    testWidgets('grupo de refs recolhe e expande', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-branch-group-locais')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('git-ref-refs/heads/main')), findsNothing);

      await tester.tap(find.byKey(const Key('git-branch-group-locais')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('git-ref-refs/heads/main')), findsOneWidget);
    });

    testWidgets('selecao de commit atualiza o inspector', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-commit-row-b111111')));
      await tester.pumpAndSettle();

      expect(find.text('feat: unicode çãü'), findsWidgets);
      final selected = target.state as GitLoaded;
      expect(selected.selectedCommitHash, middleHash);
    });

    testWidgets('selecao de arquivo mostra resumo no inspector', (
      tester,
    ) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-file-lib/b.dart')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-file-summary')), findsOneWidget);
      expect(find.textContaining('lib/b.dart'), findsWidgets);
      expect(find.textContaining('unstaged'), findsOneWidget);
    });

    testWidgets('branch remota mostra tracking do snapshot', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      expect(find.text('origin/main'), findsWidgets);
      // ahead=3 aparece uma unica vez no cabecalho; behind=1 se repete nos
      // contadores de grupos.
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('GitWorkspace estados', () {
    testWidgets('detached HEAD mostra aviso no cabecalho', (tester) async {
      final snapshot = validSnapshot();
      final target = await loadValid(
        snapshot: GitSnapshot(
          repository: const GitRepositoryState(
            kind: GitRepositoryKind.valid,
            topLevel: '/repo/raiz',
            isDetachedHead: true,
            headOid: headHash,
          ),
          commits: snapshot.commits,
        ),
      );
      await pumpWorkspace(tester, target: target);

      expect(find.text('HEAD desanexado'), findsOneWidget);
    });

    testWidgets('sem repositorio mostra mensagem acionavel', (tester) async {
      fakeRepository.nextResult = const Result.ok(
        GitSnapshot(
          repository: GitRepositoryState(kind: GitRepositoryKind.notRepository),
        ),
      );
      await cubit.setRoot(root);
      await pumpWorkspace(tester, target: cubit);

      expect(find.text('Esta pasta não é um repositório Git.'), findsOneWidget);
      expect(find.byKey(const Key('git-refresh-button')), findsOneWidget);
    });

    testWidgets('erro mostra mensagem apresentavel', (tester) async {
      fakeRepository.nextResult = const Result.error(
        GitFailureException('repositorio corrompido'),
      );
      await cubit.setRoot(root);
      await pumpWorkspace(tester, target: cubit);

      expect(find.text('repositorio corrompido'), findsOneWidget);
    });
  });

  group('GitWorkspace responsivo', () {
    testWidgets('largura ampla mostra paineis laterais fixos', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target, size: const Size(1100, 720));

      expect(find.byKey(const Key('git-branches-panel')), findsOneWidget);
      expect(find.byKey(const Key('git-commit-inspector')), findsOneWidget);
      expect(find.byKey(const Key('git-worktree-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'largura compacta recolhe branches e abre inspector como drawer',
      (tester) async {
        final target = await loadValid();
        await pumpWorkspace(tester, target: target, size: const Size(640, 700));

        expect(find.byKey(const Key('git-branches-panel')), findsNothing);
        expect(find.byKey(const Key('git-commit-inspector')), findsNothing);
        expect(find.byKey(const Key('git-worktree-panel')), findsOneWidget);

        await tester.tap(find.byKey(const Key('git-toggle-branches')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('git-branches-panel')), findsOneWidget);

        await tester.tap(find.byKey(const Key('git-toggle-branches')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('git-branches-panel')), findsNothing);

        await tester.tap(find.byKey(const Key('git-toggle-inspector')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('git-commit-inspector')), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );
  });
}

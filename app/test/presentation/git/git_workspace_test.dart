import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/presentation/desktop/git/content/git_workspace.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';

import '../shared/fakes/fake_desktop_storage_service.dart';
import 'fakes/fake_git_assistant_repository.dart';
import 'fakes/fake_git_repository.dart';
import '../shared/fakes/fake_ollama_repository.dart';

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

  GitSnapshot validSnapshot({String branch = 'main'}) => GitSnapshot(
    repository: GitRepositoryState(
      kind: GitRepositoryKind.valid,
      topLevel: '/repo/raiz',
      branch: branch,
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

  Future<GitAssistantCubit> pumpWorkspace(
    WidgetTester tester, {
    required GitCubit target,
    FakeGitAssistantRepository? assistantRepository,
    Size size = const Size(1100, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final assistant = assistantRepository ?? FakeGitAssistantRepository();
    final assistantCubit = GitAssistantCubit(assistant)..updateReadiness(true);
    final workspace = WorkspaceCubit(
      FakeOllamaRepository(),
      FakeDesktopStorageService(),
      initialRoot: root,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<GitCubit>.value(value: target),
              BlocProvider<GitAssistantCubit>.value(value: assistantCubit),
              BlocProvider<WorkspaceCubit>.value(value: workspace),
            ],
            child: const GitWorkspace(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return assistantCubit;
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

    testWidgets('seletor troca apenas para uma branch local', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-branch-selector')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('git-checkout-refs/heads/feature')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('git-checkout-refs/remotes/origin/main')),
        findsNothing,
      );

      fakeRepository.nextResult = Result.ok(validSnapshot(branch: 'feature'));
      await tester.tap(
        find.byKey(const Key('git-checkout-refs/heads/feature')),
      );
      await tester.pumpAndSettle();

      expect(
        fakeRepository.executedActions.single,
        const GitActionProposal(
          type: GitActionType.checkoutBranch,
          refName: 'feature',
        ),
      );
      expect((target.state as GitLoaded).snapshot.repository.branch, 'feature');
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

    testWidgets('cabecalho compacto preserva as acoes sem overflow', (
      tester,
    ) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target, size: const Size(500, 700));

      expect(find.byKey(const Key('git-branch-selector')), findsOneWidget);
      expect(find.byKey(const Key('git-ask-assistant-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('GitWorkspace assistente', () {
    testWidgets('Pedir ao Salvador abre o drawer com chips da selecao', (
      tester,
    ) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      expect(find.byKey(const Key('git-assistant-drawer')), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Pedir ao Salvador'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-assistant-drawer')), findsOneWidget);
      expect(find.byKey(const Key('git-assistant-chips')), findsOneWidget);
      expect(find.text('main'), findsWidgets);

      await tester.tap(find.byKey(const Key('git-assistant-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('git-assistant-drawer')), findsNothing);
    });

    testWidgets('abrir o drawer preserva a selecao de commit', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-commit-row-b111111')));
      await tester.pumpAndSettle();
      expect((target.state as GitLoaded).selectedCommitHash, middleHash);

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();

      expect((target.state as GitLoaded).selectedCommitHash, middleHash);
      expect(find.byKey(const Key('git-assistant-drawer')), findsOneWidget);
      expect(find.text('b111111'), findsWidgets);
    });

    testWidgets('envio inclui so o contexto da selecao atual', (tester) async {
      final assistant = FakeGitAssistantRepository();
      final target = await loadValid();
      await pumpWorkspace(
        tester,
        target: target,
        assistantRepository: assistant,
      );

      await tester.tap(find.byKey(const Key('git-commit-row-b111111')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('git-assistant-field')),
        'explique este commit',
      );
      await tester.tap(find.byKey(const Key('git-assistant-send')));
      await tester.pumpAndSettle();

      expect(assistant.lastContext, isNotNull);
      expect(assistant.lastContext, contains('Branch: main'));
      expect(assistant.lastContext, contains('Selecao:'));
      expect(assistant.lastContext, contains('b111111'));
    });

    testWidgets('cancelar proposta nao executa nada', (tester) async {
      final assistant = FakeGitAssistantRepository();
      final target = await loadValid();
      await pumpWorkspace(
        tester,
        target: target,
        assistantRepository: assistant,
      );

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('git-assistant-field')),
        'faça um fetch',
      );
      await tester.tap(find.byKey(const Key('git-assistant-send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-proposal-0')), findsOneWidget);
      expect(fakeRepository.executedActions, isEmpty);

      await tester.tap(find.byKey(const Key('git-cancel-proposal-0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-proposal-0')), findsNothing);
      expect(
        fakeRepository.executedActions,
        isEmpty,
        reason: 'cancelar nunca chama execute',
      );
    });

    testWidgets('confirmar proposta executa exatamente uma vez e recarrega', (
      tester,
    ) async {
      final assistant = FakeGitAssistantRepository();
      final target = await loadValid();
      await pumpWorkspace(
        tester,
        target: target,
        assistantRepository: assistant,
      );

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('git-assistant-field')),
        'proponha um fetch',
      );
      await tester.tap(find.byKey(const Key('git-assistant-send')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('git-review-proposal-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('git-action-review-dialog')), findsOneWidget);
      expect(find.text('fetch'), findsWidgets);

      final loadsBefore = fakeRepository.loadCallCount;
      fakeRepository.nextResult = Result.ok(validSnapshot());
      await tester.tap(find.byKey(const Key('git-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(fakeRepository.executedActions, hasLength(1));
      expect(fakeRepository.executedActions.single.type, GitActionType.fetch);
      expect(fakeRepository.loadCallCount, loadsBefore + 1);
      expect(find.byKey(const Key('git-proposal-0')), findsNothing);
      expect(find.byKey(const Key('git-action-review-dialog')), findsNothing);
      expect(find.byKey(const Key('git-assistant-drawer')), findsOneWidget);
      expect(find.byKey(const Key('git-branches-panel')), findsOneWidget);
      expect(find.byKey(const Key('git-commit-graph')), findsOneWidget);
      expect(find.byKey(const Key('git-worktree-panel')), findsOneWidget);
    });

    testWidgets('cancelar no dialogo nao executa', (tester) async {
      final assistant = FakeGitAssistantRepository();
      final target = await loadValid();
      await pumpWorkspace(
        tester,
        target: target,
        assistantRepository: assistant,
      );

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('git-assistant-field')),
        'proponha algo',
      );
      await tester.tap(find.byKey(const Key('git-assistant-send')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('git-review-proposal-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-dialog-cancel')));
      await tester.pumpAndSettle();

      expect(fakeRepository.executedActions, isEmpty);
      expect(find.byKey(const Key('git-proposal-0')), findsOneWidget);
    });

    testWidgets('falha da acao mostra banner e mantem o assistente', (
      tester,
    ) async {
      final assistant = FakeGitAssistantRepository();
      final target = await loadValid();
      await pumpWorkspace(
        tester,
        target: target,
        assistantRepository: assistant,
      );

      await tester.tap(find.byKey(const Key('git-ask-assistant-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('git-assistant-field')),
        'proponha um fetch',
      );
      await tester.tap(find.byKey(const Key('git-assistant-send')));
      await tester.pumpAndSettle();

      fakeRepository.nextActionResult = const Result.error(
        GitFailureException('sem rede'),
      );
      await tester.tap(find.byKey(const Key('git-review-proposal-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('git-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-action-error-banner')), findsOneWidget);
      expect(find.textContaining('sem rede'), findsOneWidget);
      expect(find.byKey(const Key('git-assistant-drawer')), findsOneWidget);
      expect(find.byKey(const Key('git-proposal-0')), findsOneWidget);
      expect((target.state as GitLoaded).snapshot.repository.branch, 'main');
    });
  });

  group('GitWorkspace fetch', () {
    testWidgets('Fetch abre revisao e cancelar nao executa', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-fetch-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('git-action-review-dialog')), findsOneWidget);
      expect(find.textContaining('acesso a rede'), findsOneWidget);
      expect(fakeRepository.executedActions, isEmpty);

      await tester.tap(find.byKey(const Key('git-dialog-cancel')));
      await tester.pumpAndSettle();

      expect(fakeRepository.executedActions, isEmpty);
      expect(find.byKey(const Key('git-action-review-dialog')), findsNothing);
    });

    testWidgets('Fetch confirmado executa uma vez e recarrega', (tester) async {
      final target = await loadValid();
      await pumpWorkspace(tester, target: target);

      await tester.tap(find.byKey(const Key('git-fetch-button')));
      await tester.pumpAndSettle();

      final loadsBefore = fakeRepository.loadCallCount;
      fakeRepository.nextResult = Result.ok(validSnapshot());
      await tester.tap(find.byKey(const Key('git-dialog-confirm')));
      await tester.pumpAndSettle();

      expect(fakeRepository.executedActions, hasLength(1));
      expect(fakeRepository.executedActions.single.type, GitActionType.fetch);
      expect(fakeRepository.loadCallCount, loadsBefore + 1);
    });
  });
}

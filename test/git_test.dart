import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

/// Fixtures reais de saida do git (formato NUL-delimited), capturados de
/// repositorios criados em disco com git 2.x: status `--porcelain=v2 --branch
/// -z`, `for-each-ref` com `%00`, `log` com `-z` e `git stash list`.
const _oidMain = '6b8dc2efa9f5ff3a00f6262229969f841cefa6fc';
const _oidMergeBase = '887182f8e6e82f52000591b1d4580f64dfecc52a';
const _oidFeature = '6a4f2ffe8a59ba72f196955d015a38dd03ae9f46';
const _oidTag = '6f38f1342128266620aa0f65c2d693cf79c7ab7a';

const _statusValid =
    '# branch.oid $_oidMain\x00'
    '# branch.head main\x00'
    '# branch.upstream origin/main\x00'
    '# branch.ab +3 -1\x00'
    '1 MM N... 100644 100644 100644 '
    '422c2b7ab3b3c668038da977e4e93a5fc623169c '
    '19e313d23cfba7d2240848ff514a19e2e5eeb954 a.txt\x00'
    '1 A. N... 000000 100644 100644 '
    '0000000000000000000000000000000000000000 '
    '3e757656cf36eca53338e520d134963a44f793f8 novo.txt\x00'
    '2 RM N... 100644 100644 100644 '
    '3e757656cf36eca53338e520d134963a44f793f8 '
    '3e757656cf36eca53338e520d134963a44f793f8 R100 renomeado.txt\x00'
    'novo nome.txt\x00'
    'u UU N... 100644 100644 100644 100644 '
    'df967b96a579e45a18b8251732d16804b2e56a55 '
    'ba2906d0666cf726c7eaadd2cd3db615dedfdf3a '
    'dd99ee2b27b9e7a8f5a1a7f9c0b9a9e6e9f3a3e2 conflito.txt\x00'
    '? arquivo com espaco.txt\x00';

const _statusDetached =
    '# branch.oid $_oidMain\x00'
    '# branch.head (detached)\x00'
    '? novo nome.txt\x00';

const _statusEmpty = '# branch.oid (initial)\x00# branch.head main\x00';

const _refsValid =
    'refs/heads/feature\x00$_oidFeature\n'
    'refs/heads/main\x00$_oidMain\n'
    'refs/remotes/origin/main\x00$_oidMain\n'
    'refs/tags/v1.0.0\x00$_oidTag\n';

const _logValid =
    '$_oidMain\x00'
    '6b8dc2\x00merge da feature\x00Test\x00t@t.co\x002026-08-29T09:44:55-03:00\x00'
    '$_oidMergeBase $_oidFeature\x00\x00\x00'
    '$_oidMergeBase\x00'
    '887182f\x00merge base\x00Test\x00t@t.co\x002026-08-29T09:44:55-03:00\x00'
    '$_oidTag\x00\x00\x00'
    '$_oidFeature\x00'
    '6a4f2ff\x00feat: unicode çãü\x00Test\x00t@t.co\x002026-08-29T09:44:55-03:00\x00'
    '$_oidTag\x00\x00\x00';

/// Saida de `log --name-status --format=%x1e -z`: cada commit separado por
/// `\x1e`, com `\x00\n` antes do primeiro par STATUS/path.
const _filesValid =
    '\x1e\x00\n'
    'M\x00a.txt\x00'
    'A\x00novo nome.txt\x00'
    '\x1e\x00\n'
    'M\x00README.md\x00'
    '\x1e\x00\n'
    'R100\x00renomeado.txt\x00'
    '\x1e\x00';

/// Historico linear de N commits respeitando `--skip`/`--max-count` dos
/// argumentos, simulando a paginacao real do git.
String _linearLog(List<String> arguments, {required int total}) {
  final skip = _argumentInt(arguments, '--skip=');
  final count = _argumentInt(arguments, '--max-count=');
  final remaining = (total - skip).clamp(0, count);
  final buffer = StringBuffer();
  for (var index = 0; index < remaining; index++) {
    final commit = index + skip;
    final hash =
        '${'${commit + 1}'.padLeft(3, '0')}'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    buffer
      ..write('$hash\x00')
      ..write('${hash.substring(0, 7)}\x00')
      ..write(
        'commit ${commit + 1}\x00Test\x00t@t.co\x00'
        '2026-08-29T09:44:55-03:00\x00',
      )
      ..write(
        '${commit > 0 ? '${'$commit'.padLeft(3, '0')}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' : ''}\x00',
      )
      ..write('\x00\x00');
  }
  return buffer.toString();
}

String _linearFiles(List<String> arguments, {required int total}) {
  final skip = _argumentInt(arguments, '--skip=');
  final count = _argumentInt(arguments, '--max-count=');
  final remaining = (total - skip).clamp(0, count);
  final buffer = StringBuffer();
  for (var index = 0; index < remaining; index++) {
    buffer
      ..write('\x1e\x00\n')
      ..write('M\x00arquivo${index + skip}.txt\x00');
  }
  buffer.write('\x1e\x00');
  return buffer.toString();
}

int _argumentInt(List<String> arguments, String prefix) {
  final argument = arguments.firstWhere(
    (candidate) => candidate.startsWith(prefix),
    orElse: () => '$prefix 0',
  );
  return int.tryParse(argument.substring(prefix.length)) ?? 0;
}

void main() {
  final root = Directory('/repo/raiz');
  late _ScriptedGitRunner runner;
  late GitClient client;

  setUp(() {
    runner = _ScriptedGitRunner();
    client = GitClient(processRunner: runner.call);
  });

  String scriptKey(List<String> arguments) {
    if (arguments[3] == 'log' && arguments[4] == '--name-status') {
      return 'log-files';
    }
    return arguments[3];
  }

  group('GitClient.discover', () {
    test('repositorio valido com branch', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
        }
        return _emptyResult();
      };

      final state = await client.discover(root);

      expect(state.isValid, isTrue);
      expect(state.kind, GitRepositoryKind.valid);
      expect(state.topLevel, '/repo/raiz');
      expect(state.branch, 'main');
      expect(state.isDetachedHead, isFalse);
    });

    test('pasta sem Git vira notRepository', () async {
      runner.script = (arguments) => _emptyResult(
        exitCode: 128,
        stderr:
            'fatal: not a git repository (or any of the parent '
            'directories): .git',
      );

      final state = await client.discover(root);

      expect(state.kind, GitRepositoryKind.notRepository);
      expect(state.isValid, isFalse);
      expect(state.topLevel, isNull);
    });

    test('top-level acima da raiz vira repositoryOutsideRoot', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo');
          case 'symbolic-ref':
            return _processResult('main');
        }
        return _emptyResult();
      };

      final state = await client.discover(root);

      expect(state.kind, GitRepositoryKind.repositoryOutsideRoot);
      expect(state.topLevel, '/repo');
    });

    test('HEAD desanexado vira branch nula com isDetachedHead', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _emptyResult(exitCode: 1);
        }
        return _emptyResult();
      };

      final state = await client.discover(root);

      expect(state.isValid, isTrue);
      expect(state.branch, isNull);
      expect(state.isDetachedHead, isTrue);
    });

    test(
      'processo ausente vira GitException, nunca excecao generica',
      () async {
        runner.script = (arguments) =>
            throw const ProcessException('git', ['-C', '/repo/raiz']);

        expect(() => client.discover(root), throwsA(isA<GitException>()));
      },
    );
  });

  group('GitClient.loadSnapshot', () {
    test('monta snapshot completo de repositorio sujo', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _processResult(_statusValid);
          case 'for-each-ref':
            return _processResult(_refsValid);
          case 'stash':
            return _processResult(
              'stash@{0}: WIP on main: $_oidMain merge da feature\n',
            );
          case 'log':
            return _processResult(_logValid);
          case 'log-files':
            return _processResult(_filesValid);
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.repository.branch, 'main');
      expect(snapshot.upstream, 'origin/main');
      expect(snapshot.ahead, 3);
      expect(snapshot.behind, 1);
      expect(snapshot.clean, isFalse);

      expect(snapshot.localBranches.map((ref) => ref.shortName), [
        'feature',
        'main',
      ]);
      expect(snapshot.remoteBranches.map((ref) => ref.shortName), [
        'origin/main',
      ]);
      expect(snapshot.tags.map((ref) => ref.shortName), ['v1.0.0']);
      expect(snapshot.stashCount, 1);

      expect(snapshot.commits, hasLength(3));
      final merge = snapshot.commits.first;
      expect(merge.isMerge, isTrue);
      expect(merge.parentHashes, [_oidMergeBase, _oidFeature]);
      expect(merge.subject, 'merge da feature');
      expect(
        snapshot.commits.last.subject,
        'feat: unicode çãü',
        reason: 'mensagens Unicode nao podem quebrar o parser',
      );

      expect(snapshot.worktree.map((entry) => entry.status), [
        GitWorktreeStatus.staged,
        GitWorktreeStatus.staged,
        GitWorktreeStatus.staged,
        GitWorktreeStatus.conflicted,
        GitWorktreeStatus.untracked,
      ]);
      expect(snapshot.worktree.map((entry) => entry.path), [
        'a.txt',
        'novo.txt',
        'renomeado.txt',
        'conflito.txt',
        'arquivo com espaco.txt',
      ]);
      final rename = snapshot.worktree[2];
      expect(rename.origPath, 'novo nome.txt');
      expect(snapshot.commitsTruncated, isFalse);

      expect(
        snapshot.commits[0].files.map((file) => '${file.status} ${file.path}'),
        ['M a.txt', 'A novo nome.txt'],
      );
      expect(snapshot.commits[1].files.map((file) => file.path), ['README.md']);
      expect(snapshot.commits[2].files.single.status, 'R');
      expect(snapshot.commits[2].files.single.path, 'renomeado.txt');
    });

    test('repositorio limpo sem refs nem commits nao quebra', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _processResult(_statusEmpty);
          case 'for-each-ref':
            return _processResult('');
          case 'stash':
            return _processResult('');
          case 'log':
            return _emptyResult(exitCode: 128);
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.clean, isTrue);
      expect(snapshot.commits, isEmpty);
      expect(snapshot.localBranches, isEmpty);
      expect(snapshot.remoteBranches, isEmpty);
      expect(snapshot.tags, isEmpty);
      expect(snapshot.stashCount, 0);
      expect(snapshot.upstream, isNull);
      expect(snapshot.repository.headOid, isNull);
    });

    test('repo vazio (branch.oid initial) nao chama log', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _processResult(_statusEmpty);
          default:
            return _processResult('');
        }
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.repository.headOid, isNull);
      expect(snapshot.commits, isEmpty);
      expect(
        runner.calls.where((arguments) => scriptKey(arguments) == 'log'),
        isEmpty,
      );
    });

    test('historico acima do limite marca truncamento', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _processResult(_statusValid);
          case 'for-each-ref':
            return _processResult(_refsValid);
          case 'stash':
            return _processResult('');
          case 'log':
            return _processResult(_logValid);
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root, maxCommits: 2);

      expect(snapshot.commits, hasLength(2));
      expect(snapshot.commitsTruncated, isTrue);
    });

    test(
      'body longo demais e truncado com flag, nao cortado em silencio',
      () async {
        final longBody = 'linha ${'x' * 5000}';
        final logWithBody =
            '$_oidMain\x00'
            '6b8dc2\x00merge da feature\x00Test\x00t@t.co\x002026-08-29T09:44:55-03:00\x00'
            '$_oidMergeBase $_oidFeature\x00$longBody\x00\x00';
        runner.script = (arguments) {
          switch (scriptKey(arguments)) {
            case 'rev-parse':
              return _processResult('/repo/raiz');
            case 'symbolic-ref':
              return _processResult('main');
            case 'status':
              return _processResult(_statusValid);
            case 'for-each-ref':
              return _processResult(_refsValid);
            case 'stash':
              return _processResult('');
            case 'log':
              return _processResult(logWithBody);
          }
          return _emptyResult();
        };

        final snapshot = await client.loadSnapshot(root);

        final commit = snapshot.commits.single;
        expect(commit.bodyTruncated, isTrue);
        expect(commit.body.length, lessThan(longBody.length));
      },
    );

    test('pasta sem Git retorna snapshot vazio, nao erro', () async {
      runner.script = (arguments) {
        if (scriptKey(arguments) == 'rev-parse') {
          return _emptyResult(exitCode: 128);
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.repository.kind, GitRepositoryKind.notRepository);
      expect(snapshot.commits, isEmpty);
      expect(snapshot.worktree, isEmpty);
    });

    test('repositorio acima da raiz retorna fora de escopo', () async {
      runner.script = (arguments) {
        if (scriptKey(arguments) == 'rev-parse') {
          return _processResult('/repo');
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.repository.kind, GitRepositoryKind.repositoryOutsideRoot);
      expect(snapshot.repository.topLevel, '/repo');
    });

    test('HEAD desanexado carrega snapshot sem branch', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _emptyResult(exitCode: 1);
          case 'status':
            return _processResult(_statusDetached);
          case 'for-each-ref':
            return _processResult(_refsValid);
          case 'stash':
            return _processResult('');
          case 'log':
            return _processResult(_logValid);
        }
        return _emptyResult();
      };

      final snapshot = await client.loadSnapshot(root);

      expect(snapshot.repository.isValid, isTrue);
      expect(snapshot.repository.isDetachedHead, isTrue);
      expect(snapshot.repository.branch, isNull);
      expect(snapshot.worktree.single.status, GitWorktreeStatus.untracked);
    });

    test('falha de processo vira GitException', () async {
      runner.script = (arguments) {
        if (scriptKey(arguments) == 'rev-parse') {
          return _processResult('/repo/raiz');
        }
        if (scriptKey(arguments) == 'symbolic-ref') {
          return _processResult('main');
        }
        throw const ProcessException('git', ['status']);
      };

      expect(() => client.loadSnapshot(root), throwsA(isA<GitException>()));
    });

    test('codigo de saida inesperado no status vira GitException', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _emptyResult(
              exitCode: 1,
              stderr: 'fatal: repositorio corrompido',
            );
        }
        return _emptyResult();
      };

      expect(() => client.loadSnapshot(root), throwsA(isA<GitException>()));
    });

    test('argumentos sempre partem de -C com a raiz, sem shell', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'rev-parse':
            return _processResult('/repo/raiz');
          case 'symbolic-ref':
            return _processResult('main');
          case 'status':
            return _processResult('');
          case 'for-each-ref':
            return _processResult('');
          case 'stash':
            return _processResult('');
          case 'log':
            return _processResult(_logValid);
        }
        return _emptyResult();
      };

      await client.loadSnapshot(root);

      expect(runner.calls, isNotEmpty);
      for (final arguments in runner.calls) {
        expect(arguments[0], 'git');
        expect(arguments[1], '-C');
        expect(arguments[2], root.path);
      }
    });

    test(
      'loadMoreCommits pagina sem duplicar hashes e marca hasMore',
      () async {
        runner.script = (arguments) {
          switch (scriptKey(arguments)) {
            case 'rev-parse':
              return _processResult('/repo/raiz');
            case 'symbolic-ref':
              return _processResult('main');
            case 'status':
              return _processResult(_statusValid);
            case 'for-each-ref':
              return _processResult(_refsValid);
            case 'stash':
              return _processResult('');
            case 'log':
              return _processResult(_linearLog(arguments, total: 5));
            case 'log-files':
              return _processResult(_linearFiles(arguments, total: 5));
          }
          return _emptyResult();
        };

        final page = await client.loadMoreCommits(root, skip: 0, count: 2);

        expect(page.commits, hasLength(2));
        expect(page.hasMore, isTrue);
        expect(
          page.commits.map((commit) => commit.hash).toSet(),
          hasLength(2),
          reason: 'hashes nao podem duplicar dentro da pagina',
        );
        expect(page.commits.first.files.single.path, 'arquivo0.txt');

        final skipArguments = runner.calls.where(
          (arguments) => arguments.contains('--skip=0'),
        );
        expect(skipArguments, isNotEmpty);
      },
    );

    test('loadMoreCommits ultima pagina retorna hasMore false', () async {
      runner.script = (arguments) {
        switch (scriptKey(arguments)) {
          case 'log':
            return _processResult(_linearLog(arguments, total: 5));
          case 'log-files':
            return _processResult(_linearFiles(arguments, total: 5));
        }
        return _emptyResult();
      };

      final page = await client.loadMoreCommits(root, skip: 3, count: 3);

      expect(page.commits, hasLength(2));
      expect(page.hasMore, isFalse);
      expect(page.commits.map((commit) => commit.hash), [
        '004aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '005aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ]);
    });
  });

  group('GitActionProposal', () {
    test('enum representa todas as operacoes Git tipadas', () {
      final names = GitActionType.values.map((type) => type.name).toList();
      expect(names, [
        'fetch',
        'pull',
        'push',
        'pushForce',
        'createBranch',
        'checkoutBranch',
        'stage',
        'unstage',
        'commit',
        'merge',
        'rebase',
        'resetSoft',
        'resetMixed',
        'resetHard',
        'cleanForce',
        'restoreFile',
        'removeFile',
        'moveFile',
        'deleteBranch',
        'deleteBranchForce',
        'createTag',
        'deleteTag',
        'stashPush',
        'stashPop',
        'stashApply',
        'stashDrop',
        'cherryPick',
        'revert',
        'amendCommit',
        'mergeAbort',
        'rebaseAbort',
        'rebaseContinue',
        'remoteAdd',
        'remoteRemove',
      ]);
      expect(names, hasLength(34));
    });

    test('classifica 12 operacoes riscosas e repassa o risco', () {
      const risky = {
        GitActionType.fetch,
        GitActionType.pull,
        GitActionType.push,
        GitActionType.pushForce,
        GitActionType.resetHard,
        GitActionType.cleanForce,
        GitActionType.restoreFile,
        GitActionType.removeFile,
        GitActionType.deleteBranchForce,
        GitActionType.deleteTag,
        GitActionType.stashDrop,
        GitActionType.amendCommit,
      };
      for (final type in GitActionType.values) {
        expect(
          type.risk,
          risky.contains(type) ? GitActionRisk.risky : GitActionRisk.normal,
          reason: type.name,
        );
        expect(
          GitActionProposal(type: type).risk,
          type.risk,
          reason: type.name,
        );
      }
    });

    test('resumo descreve o tipo e a selecao', () {
      expect(
        const GitActionProposal(type: GitActionType.fetch).summary,
        'fetch',
      );
      expect(
        const GitActionProposal(
          type: GitActionType.createBranch,
          refName: 'feature-x',
        ).summary,
        'criar branch feature-x',
      );
      expect(
        const GitActionProposal(
          type: GitActionType.commit,
          message: 'corrige parse do status',
        ).summary,
        'commit: corrige parse do status',
      );
      expect(
        const GitActionProposal(
          type: GitActionType.stage,
          paths: ['a.txt', 'b.txt'],
        ).summary,
        'stage: a.txt, b.txt',
      );
    });
  });

  group('GitActionExecutor', () {
    test('operacoes de rede usam argumentos fixos sem shell', () async {
      final seen = <List<String>>[];
      runner.script = (arguments) {
        seen.add(arguments);
        return _processResult('');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      await executor.execute(
        const GitActionProposal(type: GitActionType.push, refName: 'origin'),
        root,
      );
      await executor.execute(
        const GitActionProposal(type: GitActionType.pushForce),
        root,
      );
      await executor.execute(
        const GitActionProposal(type: GitActionType.pull),
        root,
      );
      await executor.execute(
        const GitActionProposal(type: GitActionType.fetch),
        root,
      );

      expect(seen, [
        ['git', '-C', root.path, 'push', 'origin'],
        ['git', '-C', root.path, 'push', '--force'],
        ['git', '-C', root.path, 'pull'],
        ['git', '-C', root.path, 'fetch'],
      ]);
    });

    test('operacoes riscosas usam argumentos fixos sem shell', () async {
      final seen = <List<String>>[];
      runner.script = (arguments) {
        seen.add(arguments);
        return _processResult('');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      final actions = const [
        GitActionProposal(type: GitActionType.resetHard, refName: 'HEAD~1'),
        GitActionProposal(type: GitActionType.cleanForce),
        GitActionProposal(type: GitActionType.restoreFile, paths: ['a.txt']),
        GitActionProposal(type: GitActionType.removeFile, paths: ['a.txt']),
        GitActionProposal(
          type: GitActionType.deleteBranchForce,
          refName: 'feature/x',
        ),
        GitActionProposal(type: GitActionType.deleteTag, refName: 'v1.0.0'),
        GitActionProposal(type: GitActionType.stashDrop),
        GitActionProposal(
          type: GitActionType.amendCommit,
          message: 'corrige mensagem',
        ),
      ];
      for (final action in actions) {
        await executor.execute(action, root);
      }

      expect(seen, [
        ['git', '-C', root.path, 'reset', '--hard', 'HEAD~1'],
        ['git', '-C', root.path, 'clean', '-fd'],
        ['git', '-C', root.path, 'restore', 'a.txt'],
        ['git', '-C', root.path, 'rm', 'a.txt'],
        ['git', '-C', root.path, 'branch', '-D', 'feature/x'],
        ['git', '-C', root.path, 'tag', '-d', 'v1.0.0'],
        ['git', '-C', root.path, 'stash', 'drop'],
        ['git', '-C', root.path, 'commit', '--amend', '-m', 'corrige mensagem'],
      ]);
    });

    test('demais operacoes usam argumentos fixos sem shell', () async {
      final seen = <List<String>>[];
      runner.script = (arguments) {
        seen.add(arguments);
        return _processResult('');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      final actions = const [
        GitActionProposal(type: GitActionType.resetSoft, refName: 'HEAD^'),
        GitActionProposal(type: GitActionType.resetMixed),
        GitActionProposal(
          type: GitActionType.moveFile,
          paths: ['old.txt', 'new.txt'],
        ),
        GitActionProposal(type: GitActionType.deleteBranch, refName: 'feature'),
        GitActionProposal(type: GitActionType.createTag, refName: 'v1.0.0'),
        GitActionProposal(type: GitActionType.stashPush, message: 'wip'),
        GitActionProposal(type: GitActionType.stashPop),
        GitActionProposal(type: GitActionType.stashApply),
        GitActionProposal(type: GitActionType.cherryPick, refName: 'a1b2c3d'),
        GitActionProposal(type: GitActionType.revert, refName: 'a1b2c3d'),
        GitActionProposal(type: GitActionType.mergeAbort),
        GitActionProposal(type: GitActionType.rebaseAbort),
        GitActionProposal(type: GitActionType.rebaseContinue),
        GitActionProposal(
          type: GitActionType.remoteAdd,
          refName: 'origin',
          message: 'https://example.com/repo.git',
        ),
        GitActionProposal(type: GitActionType.remoteRemove, refName: 'origin'),
      ];
      for (final action in actions) {
        await executor.execute(action, root);
      }

      expect(seen, [
        ['git', '-C', root.path, 'reset', '--soft', 'HEAD^'],
        ['git', '-C', root.path, 'reset'],
        ['git', '-C', root.path, 'mv', 'old.txt', 'new.txt'],
        ['git', '-C', root.path, 'branch', '-d', 'feature'],
        ['git', '-C', root.path, 'tag', 'v1.0.0'],
        ['git', '-C', root.path, 'stash', 'push', '-m', 'wip'],
        ['git', '-C', root.path, 'stash', 'pop'],
        ['git', '-C', root.path, 'stash', 'apply'],
        ['git', '-C', root.path, 'cherry-pick', 'a1b2c3d'],
        ['git', '-C', root.path, 'revert', '--no-edit', 'a1b2c3d'],
        ['git', '-C', root.path, 'merge', '--abort'],
        ['git', '-C', root.path, 'rebase', '--abort'],
        ['git', '-C', root.path, 'rebase', '--continue'],
        [
          'git',
          '-C',
          root.path,
          'remote',
          'add',
          'origin',
          'https://example.com/repo.git',
        ],
        ['git', '-C', root.path, 'remote', 'remove', 'origin'],
      ]);
    });

    test('fetch usa argumentos fixos sem shell', () async {
      runner.script = (arguments) {
        expect(arguments, ['git', '-C', root.path, 'fetch']);
        return _processResult('done');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      final result = await executor.execute(
        const GitActionProposal(type: GitActionType.fetch),
        root,
      );

      expect(result, 'done');
    });

    test('criar e trocar branch validam a ref antes do processo', () async {
      final seen = <List<String>>[];
      runner.script = (arguments) {
        seen.add(arguments);
        return _processResult('');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      await executor.execute(
        const GitActionProposal(
          type: GitActionType.createBranch,
          refName: 'feature/x-1',
        ),
        root,
      );
      await executor.execute(
        const GitActionProposal(
          type: GitActionType.checkoutBranch,
          refName: 'main',
        ),
        root,
      );

      expect(seen[0], [
        'git',
        '-C',
        root.path,
        'checkout',
        '-b',
        'feature/x-1',
      ]);
      expect(seen[1], ['git', '-C', root.path, 'checkout', 'main']);
    });

    test('stage e unstage passam apenas caminhos validos', () async {
      final seen = <List<String>>[];
      runner.script = (arguments) {
        seen.add(arguments);
        return _processResult('');
      };
      final executor = GitActionExecutor(processRunner: runner.call);

      await executor.execute(
        const GitActionProposal(
          type: GitActionType.stage,
          paths: ['src/a.dart', 'README.md'],
        ),
        root,
      );
      await executor.execute(
        const GitActionProposal(
          type: GitActionType.unstage,
          paths: ['src/a.dart'],
        ),
        root,
      );

      expect(seen[0], [
        'git',
        '-C',
        root.path,
        'add',
        'src/a.dart',
        'README.md',
      ]);
      expect(seen[1], [
        'git',
        '-C',
        root.path,
        'restore',
        '--staged',
        'src/a.dart',
      ]);
    });

    test(
      'commit e merge passam mensagem e ref sem flags destrutivas',
      () async {
        final seen = <List<String>>[];
        runner.script = (arguments) {
          seen.add(arguments);
          return _processResult('');
        };
        final executor = GitActionExecutor(processRunner: runner.call);

        await executor.execute(
          const GitActionProposal(
            type: GitActionType.commit,
            message: 'feat: ajusta indices',
          ),
          root,
        );
        await executor.execute(
          const GitActionProposal(
            type: GitActionType.merge,
            refName: 'feature',
          ),
          root,
        );
        await executor.execute(
          const GitActionProposal(type: GitActionType.rebase, refName: 'main'),
          root,
        );

        expect(seen[0], [
          'git',
          '-C',
          root.path,
          'commit',
          '-m',
          'feat: ajusta indices',
        ]);
        expect(seen[1], [
          'git',
          '-C',
          root.path,
          'merge',
          '--no-edit',
          'feature',
        ]);
        expect(seen[2], ['git', '-C', root.path, 'rebase', 'main']);
      },
    );

    test('aceita refs Git comuns e rejeita refs inseguras', () async {
      final executor = GitActionExecutor(processRunner: runner.call);
      for (final ref in [
        'HEAD~1',
        'HEAD^',
        'a1b2c3d',
        'a1b2c3d4e5f6789012345678901234567890abcd',
        'v1.0.0',
      ]) {
        executor.validate(
          GitActionProposal(type: GitActionType.checkoutBranch, refName: ref),
          root,
        );
      }
      for (final ref in ['--hard', 'a..b', 'feature@{1}', '-x', 'com espaco']) {
        await expectLater(
          executor.execute(
            GitActionProposal(type: GitActionType.checkoutBranch, refName: ref),
            root,
          ),
          throwsA(isA<GitException>()),
          reason: 'ref invalida: $ref',
        );
      }
      expect(runner.calls, isEmpty);
    });

    test('rejeita caminho absoluto, com .. ou opcao', () async {
      final executor = GitActionExecutor(processRunner: runner.call);
      for (final path in ['/etc/passwd', '../fora.txt', '-p']) {
        await expectLater(
          executor.execute(
            GitActionProposal(type: GitActionType.stage, paths: [path]),
            root,
          ),
          throwsA(isA<GitException>()),
          reason: 'caminho invalido: $path',
        );
      }
      expect(runner.calls, isEmpty);
    });

    test('rejeita mensagem de commit vazia', () async {
      final executor = GitActionExecutor(processRunner: runner.call);

      await expectLater(
        executor.execute(
          const GitActionProposal(type: GitActionType.commit, message: '  '),
          root,
        ),
        throwsA(isA<GitException>()),
      );
      expect(runner.calls, isEmpty);
    });

    test('rejeita ref vazia em criar/trocar/merge/rebase', () async {
      final executor = GitActionExecutor(processRunner: runner.call);
      for (final type in [
        GitActionType.createBranch,
        GitActionType.checkoutBranch,
        GitActionType.merge,
        GitActionType.rebase,
      ]) {
        await expectLater(
          executor.execute(GitActionProposal(type: type), root),
          throwsA(isA<GitException>()),
        );
      }
      expect(runner.calls, isEmpty);
    });

    test('falha de processo vira GitException com a saida', () async {
      runner.script = (arguments) =>
          _emptyResult(exitCode: 1, stderr: 'fatal: conflito no merge');
      final executor = GitActionExecutor(processRunner: runner.call);

      await expectLater(
        executor.execute(
          const GitActionProposal(type: GitActionType.merge, refName: 'x'),
          root,
        ),
        throwsA(
          isA<GitException>().having(
            (error) => error.message,
            'message',
            contains('conflito'),
          ),
        ),
      );
    });
  });
}

ProcessResult _processResult(
  String stdout, {
  int exitCode = 0,
  String stderr = '',
}) => ProcessResult(0, exitCode, stdout, stderr);

ProcessResult _emptyResult({int exitCode = 0, String stderr = ''}) =>
    ProcessResult(0, exitCode, '', stderr);

class _ScriptedGitRunner {
  Object? Function(List<String> arguments)? script;
  final List<List<String>> calls = [];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    final full = [executable, ...arguments];
    calls.add(full);
    final response = script!(full);
    if (response is ProcessResult) return response;
    throw StateError('script sem resposta para $full');
  }
}

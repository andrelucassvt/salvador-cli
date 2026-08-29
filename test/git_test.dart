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

void main() {
  final root = Directory('/repo/raiz');
  late _ScriptedGitRunner runner;
  late GitClient client;

  setUp(() {
    runner = _ScriptedGitRunner();
    client = GitClient(processRunner: runner.call);
  });

  String scriptKey(List<String> arguments) => arguments[3];

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

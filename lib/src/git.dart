import 'dart:async';
import 'dart:io';

/// Runner injetavel para o processo `git`. Recebe o executavel e os
/// argumentos completos (incluindo `-C <root>`); nunca usa shell.
typedef GitProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Estado de descoberta de um diretorio como repositorio Git.
enum GitRepositoryKind { valid, notRepository, repositoryOutsideRoot }

/// Estado de um arquivo no worktree.
enum GitWorktreeStatus { staged, unstaged, untracked, conflicted }

/// Resultado da validacao de um diretorio contra `rev-parse --show-toplevel`.
class GitRepositoryState {
  const GitRepositoryState({
    this.kind = GitRepositoryKind.notRepository,
    this.isDetachedHead = false,
    this.topLevel,
    this.branch,
    this.headOid,
  });

  final GitRepositoryKind kind;
  final bool isDetachedHead;
  final String? topLevel;
  final String? branch;
  final String? headOid;

  bool get isValid => kind == GitRepositoryKind.valid;

  @override
  String toString() =>
      'GitRepositoryState(kind: $kind, topLevel: $topLevel, '
      'branch: $branch, isDetachedHead: $isDetachedHead, '
      'headOid: $headOid)';
}

/// Uma mudanca no worktree (staged, unstaged, untracked ou conflicted).
class GitWorktreeEntry {
  const GitWorktreeEntry({
    required this.path,
    this.origPath,
    required this.status,
  });

  final String path;
  final String? origPath;
  final GitWorktreeStatus status;

  @override
  String toString() => 'GitWorktreeEntry($status $path)';
}

/// Uma ref do repositorio: branch local, remota ou tag.
class GitRef {
  const GitRef({required this.name, required this.hash});

  final String name;
  final String hash;

  String get shortName {
    const prefixes = ['refs/heads/', 'refs/remotes/', 'refs/tags/'];
    for (final prefix in prefixes) {
      if (name.startsWith(prefix)) return name.substring(prefix.length);
    }
    return name;
  }

  @override
  String toString() => 'GitRef($name @ ${hash.substring(0, 7)})';
}

/// Um commit do historico limitado do snapshot.
class GitCommit {
  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.subject,
    required this.authorName,
    required this.authorEmail,
    required this.authorDate,
    this.parentHashes = const [],
    this.body = '',
    this.bodyTruncated = false,
  });

  final String hash;
  final String shortHash;
  final String subject;
  final String authorName;
  final String authorEmail;
  final DateTime authorDate;
  final List<String> parentHashes;
  final String body;
  final bool bodyTruncated;

  bool get isMerge => parentHashes.length > 1;

  @override
  String toString() => 'GitCommit($shortHash $subject)';
}

/// Snapshot somente leitura de um repositorio Git na raiz vinculada.
class GitSnapshot {
  const GitSnapshot({
    required this.repository,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.localBranches = const [],
    this.remoteBranches = const [],
    this.tags = const [],
    this.stashCount = 0,
    this.commits = const [],
    this.commitsTruncated = false,
    this.worktree = const [],
  });

  final GitRepositoryState repository;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<GitRef> localBranches;
  final List<GitRef> remoteBranches;
  final List<GitRef> tags;
  final int stashCount;
  final List<GitCommit> commits;
  final bool commitsTruncated;
  final List<GitWorktreeEntry> worktree;

  bool get clean => worktree.isEmpty;

  @override
  String toString() =>
      'GitSnapshot(branch: ${repository.branch}, '
      'commits: ${commits.length}, worktree: ${worktree.length}, '
      'clean: $clean)';
}

/// Falha esperada do processo ou do parsing Git. Nunca `Exception` generica.
class GitException implements Exception {
  const GitException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Cliente Git confinado: roda `git -C <root> <comando>` com `runInShell:
/// false`, valida o top-level resolvido contra a raiz vinculada e nunca
/// interpola argumentos do usuario em shell.
class GitClient {
  GitClient({
    GitProcessRunner? processRunner,
    this.timeout = const Duration(seconds: 15),
  }) : _processRunner = processRunner ?? _defaultRunner;

  static const maxCommitsDefault = 100;
  static const _executable = 'git';
  static const _maxBodyLength = 4000;

  final GitProcessRunner _processRunner;
  final Duration timeout;

  /// Valida [root] contra `rev-parse --show-toplevel` por caminhos resolvidos
  /// e distingue repositório válido, pasta sem Git e repositório acima da raiz.
  Future<GitRepositoryState> discover(Directory root) async {
    final revParse = await _run(root, const ['rev-parse', '--show-toplevel']);
    if (revParse.exitCode != 0) {
      return const GitRepositoryState(kind: GitRepositoryKind.notRepository);
    }
    final topLevel = _normalizePath((revParse.stdout as String).trim());
    if (topLevel.isEmpty) {
      return const GitRepositoryState(kind: GitRepositoryKind.notRepository);
    }
    final resolvedRoot = _resolveRoot(root);
    if (topLevel != resolvedRoot) {
      return GitRepositoryState(
        kind: GitRepositoryKind.repositoryOutsideRoot,
        topLevel: topLevel,
      );
    }

    final branchResult = await _run(root, const [
      'symbolic-ref',
      '--quiet',
      '--short',
      'HEAD',
    ]);
    if (branchResult.exitCode != 0) {
      return GitRepositoryState(
        kind: GitRepositoryKind.valid,
        topLevel: topLevel,
        isDetachedHead: true,
      );
    }
    final branch = (branchResult.stdout as String).trim();
    return GitRepositoryState(
      kind: GitRepositoryKind.valid,
      topLevel: topLevel,
      branch: branch.isEmpty ? null : branch,
    );
  }

  /// Carrega o snapshot somente leitura do repositório na raiz vinculada.
  /// Repositório inválido ou fora da raiz retorna um snapshot vazio com o
  /// estado correspondente; falha de processo/código de saída vira
  /// [GitException].
  Future<GitSnapshot> loadSnapshot(
    Directory root, {
    int maxCommits = maxCommitsDefault,
  }) async {
    final repository = await discover(root);
    if (!repository.isValid) {
      return GitSnapshot(repository: repository);
    }

    final statusResult = await _run(root, const [
      'status',
      '--porcelain=v2',
      '--branch',
      '-z',
      '--untracked-files=all',
    ]);
    if (statusResult.exitCode != 0) {
      throw GitException(_failureMessage('git status', statusResult));
    }
    final status = _parseStatus(statusResult.stdout as String);

    final refsResult = await _run(root, const [
      'for-each-ref',
      '--format=%(refname)%00%(objectname)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ]);
    if (refsResult.exitCode != 0) {
      throw GitException(_failureMessage('git for-each-ref', refsResult));
    }
    final refs = _parseRefs(refsResult.stdout as String);

    final stashResult = await _run(root, const ['stash', 'list']);
    if (stashResult.exitCode != 0) {
      throw GitException(_failureMessage('git stash list', stashResult));
    }
    final stashCount = _parseStashCount(stashResult.stdout as String);

    var commits = const <GitCommit>[];
    var commitsTruncated = false;
    if (status.headOid != null) {
      final logResult = await _run(root, [
        'log',
        '--format=%H%x00%h%x00%s%x00%an%x00%ae%x00%aI%x00%P%x00%b%x00',
        '-z',
        '--max-count=${maxCommits + 1}',
      ]);
      if (logResult.exitCode != 0) {
        throw GitException(_failureMessage('git log', logResult));
      }
      final parsed = _parseLog(logResult.stdout as String);
      commitsTruncated = parsed.length > maxCommits;
      commits = commitsTruncated ? parsed.sublist(0, maxCommits) : parsed;
    }

    return GitSnapshot(
      repository: GitRepositoryState(
        kind: GitRepositoryKind.valid,
        topLevel: repository.topLevel,
        branch: repository.branch,
        isDetachedHead: repository.isDetachedHead,
        headOid: status.headOid,
      ),
      upstream: status.upstream,
      ahead: status.ahead,
      behind: status.behind,
      localBranches: refs
          .where((ref) => ref.name.startsWith('refs/heads/'))
          .toList(growable: false),
      remoteBranches: refs
          .where((ref) => ref.name.startsWith('refs/remotes/'))
          .toList(growable: false),
      tags: refs
          .where((ref) => ref.name.startsWith('refs/tags/'))
          .toList(growable: false),
      stashCount: stashCount,
      commits: commits,
      commitsTruncated: commitsTruncated,
      worktree: status.worktree,
    );
  }

  Future<ProcessResult> _run(Directory root, List<String> arguments) async {
    final ProcessResult result;
    try {
      result = await _processRunner(_executable, [
        '-C',
        root.path,
        ...arguments,
      ]).timeout(timeout);
    } on TimeoutException {
      throw const GitException('git excedeu o limite de tempo.');
    } on ProcessException catch (error) {
      throw GitException(
        'Nao foi possivel executar git: ${error.message}',
        cause: error,
      );
    }
    return result;
  }

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);

  static String _resolveRoot(Directory root) {
    try {
      return _normalizePath(root.resolveSymbolicLinksSync());
    } on FileSystemException {
      return _normalizePath(root.absolute.path);
    }
  }

  static String _normalizePath(String path) {
    var normalized = path.trim();
    while (normalized.endsWith('/') || normalized.endsWith('\\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _failureMessage(String command, ProcessResult result) {
    final details = ((result.stderr as String?) ?? '').trim();
    if (details.isNotEmpty) return details;
    return '$command terminou com codigo ${result.exitCode}';
  }

  /// Resultado intermediario do status, antes de virar [GitSnapshot].
  static ({
    String? headOid,
    bool detached,
    String? upstream,
    int ahead,
    int behind,
    List<GitWorktreeEntry> worktree,
  })
  _parseStatus(String output) {
    String? headOid;
    var detached = false;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    final worktree = <GitWorktreeEntry>[];

    final records = output.split('\x00');
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      if (record.isEmpty) continue;
      if (record.startsWith('# ')) {
        final rest = record.substring(2);
        if (rest.startsWith('branch.oid ')) {
          final oid = rest.substring('branch.oid '.length).trim();
          headOid = oid == '(initial)' ? null : oid;
        } else if (rest.startsWith('branch.head ')) {
          final name = rest.substring('branch.head '.length).trim();
          if (name == '(detached)') detached = true;
        } else if (rest.startsWith('branch.upstream ')) {
          upstream = rest.substring('branch.upstream '.length).trim();
        } else if (rest.startsWith('branch.ab ')) {
          final match = RegExp(r'\+(\d+) -(\d+)').firstMatch(rest);
          if (match != null) {
            ahead = int.tryParse(match[1]!) ?? 0;
            behind = int.tryParse(match[2]!) ?? 0;
          }
        }
        continue;
      }
      if (record.startsWith('? ')) {
        worktree.add(
          GitWorktreeEntry(
            path: record.substring(2),
            status: GitWorktreeStatus.untracked,
          ),
        );
        continue;
      }

      final tokens = record.split(' ');
      final kind = tokens.first;
      switch (kind) {
        case '1':
          final path = tokens.length > 8 ? tokens.sublist(8).join(' ') : '';
          if (path.isEmpty) continue;
          worktree.add(
            GitWorktreeEntry(
              path: path,
              status: _statusFromXY(tokens.length > 1 ? tokens[1] : ''),
            ),
          );
        case '2':
          final path = tokens.length > 9 ? tokens.sublist(9).join(' ') : '';
          if (path.isEmpty) continue;
          var origPath = index + 1 < records.length ? records[index + 1] : null;
          if (origPath != null && origPath.isEmpty) origPath = null;
          if (origPath != null) index++;
          worktree.add(
            GitWorktreeEntry(
              path: path,
              origPath: origPath,
              status: _statusFromXY(tokens.length > 1 ? tokens[1] : ''),
            ),
          );
        case 'u':
          final path = tokens.length > 10 ? tokens.sublist(10).join(' ') : '';
          if (path.isEmpty) continue;
          worktree.add(
            GitWorktreeEntry(path: path, status: GitWorktreeStatus.conflicted),
          );
      }
    }

    return (
      headOid: headOid,
      detached: detached,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      worktree: worktree,
    );
  }

  static GitWorktreeStatus _statusFromXY(String xy) {
    if (xy.isEmpty || xy[0] == '.') return GitWorktreeStatus.unstaged;
    return GitWorktreeStatus.staged;
  }

  static List<GitRef> _parseRefs(String output) {
    final refs = <GitRef>[];
    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;
      final parts = line.split('\x00');
      if (parts.length != 2) continue;
      final name = parts[0].trim();
      final hash = parts[1].trim();
      if (name.isEmpty || hash.isEmpty) continue;
      refs.add(GitRef(name: name, hash: hash));
    }
    return refs;
  }

  static int _parseStashCount(String output) {
    var count = 0;
    for (final line in output.split('\n')) {
      if (line.trim().isNotEmpty) count++;
    }
    return count;
  }

  static List<GitCommit> _parseLog(String output) {
    // Com `git log -z`, cada commit termina com NUL alem dos separadores de
    // campo do --format, entao cada registro ocupa 9 campos (8 de conteudo +
    // 1 separador vazio).
    final fields = output.split('\x00');
    final commits = <GitCommit>[];
    for (var index = 0; index + 7 < fields.length; index += 9) {
      final hash = fields[index].trim();
      if (hash.isEmpty) continue;
      final body = fields[index + 7];
      commits.add(
        GitCommit(
          hash: hash,
          shortHash: fields[index + 1].trim(),
          subject: fields[index + 2].trim(),
          authorName: fields[index + 3].trim(),
          authorEmail: fields[index + 4].trim(),
          authorDate: DateTime.parse(fields[index + 5].trim()),
          parentHashes: fields[index + 6]
              .split(' ')
              .where((parent) => parent.trim().isNotEmpty)
              .toList(growable: false),
          body: body.length > _maxBodyLength
              ? body.substring(0, _maxBodyLength)
              : body,
          bodyTruncated: body.length > _maxBodyLength,
        ),
      );
    }
    return commits;
  }
}

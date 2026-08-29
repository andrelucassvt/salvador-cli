import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

/// Estados do modo Git no desktop: vazio (sem raiz), carregando (preservando
/// o snapshot anterior), pronto, fora de escopo, nao-repositorio e erro
/// apresentavel.
@immutable
sealed class GitState {
  const GitState();

  @override
  String toString();
}

/// Sem raiz vinculada: o modo Git fica vazio ate um projeto ser aberto.
class GitEmpty extends GitState {
  const GitEmpty();

  @override
  String toString() => 'GitEmpty';
}

/// Carregando snapshot; [previous] preserva os dados exibidos enquanto
/// atualiza, quando ja havia um snapshot valido.
class GitLoading extends GitState {
  const GitLoading({this.previous});

  final GitLoaded? previous;

  @override
  String toString() =>
      'GitLoading(previous: ${previous == null ? 'nenhum' : 'snapshot'})';
}

/// Snapshot valido do repositorio na raiz vinculada, com selecoes, filtro e
/// historico paginado derivados sem mutar os dados brutos.
@immutable
class GitLoaded extends GitState {
  const GitLoaded({
    required this.snapshot,
    this.commits,
    this.hasMoreCommits = false,
    this.loadingMore = false,
    this.searchQuery = '',
    this.selectedRef,
    this.selectedCommitHash,
    this.selectedFilePath,
  });

  final GitSnapshot snapshot;

  /// Historico derivado: `snapshot.commits` + paginas carregadas por
  /// `loadMore`. Quando null, usa `snapshot.commits`.
  final List<GitCommit>? commits;
  final bool hasMoreCommits;
  final bool loadingMore;

  /// Filtro case-insensitive aplicado a branches, tags e worktree.
  final String searchQuery;
  final String? selectedRef;
  final String? selectedCommitHash;
  final String? selectedFilePath;

  List<GitCommit> get visibleCommits => commits ?? snapshot.commits;

  List<GitRef> get visibleLocalBranches => _filterRefs(snapshot.localBranches);

  List<GitRef> get visibleRemoteBranches =>
      _filterRefs(snapshot.remoteBranches);

  List<GitRef> get visibleTags => _filterRefs(snapshot.tags);

  List<GitWorktreeEntry> get visibleWorktree {
    final query = searchQuery.toLowerCase();
    if (query.isEmpty) return snapshot.worktree;
    return snapshot.worktree
        .where((entry) => entry.path.toLowerCase().contains(query))
        .toList(growable: false);
  }

  GitCommit? get selectedCommit {
    final hash = selectedCommitHash;
    if (hash == null) return null;
    for (final commit in visibleCommits) {
      if (commit.hash == hash) return commit;
    }
    return null;
  }

  List<GitRef> _filterRefs(List<GitRef> refs) {
    final query = searchQuery.toLowerCase();
    if (query.isEmpty) return refs;
    return refs
        .where((ref) => ref.shortName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  GitLoaded copyWith({
    GitSnapshot? snapshot,
    List<GitCommit>? commits,
    bool clearCommits = false,
    bool? hasMoreCommits,
    bool? loadingMore,
    String? searchQuery,
    bool clearSearch = false,
    String? selectedRef,
    bool clearSelectedRef = false,
    String? selectedCommitHash,
    bool clearSelectedCommit = false,
    String? selectedFilePath,
    bool clearSelectedFile = false,
  }) {
    return GitLoaded(
      snapshot: snapshot ?? this.snapshot,
      commits: clearCommits ? null : (commits ?? this.commits),
      hasMoreCommits: hasMoreCommits ?? this.hasMoreCommits,
      loadingMore: loadingMore ?? this.loadingMore,
      searchQuery: clearSearch ? '' : (searchQuery ?? this.searchQuery),
      selectedRef: clearSelectedRef ? null : (selectedRef ?? this.selectedRef),
      selectedCommitHash: clearSelectedCommit
          ? null
          : (selectedCommitHash ?? this.selectedCommitHash),
      selectedFilePath: clearSelectedFile
          ? null
          : (selectedFilePath ?? this.selectedFilePath),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GitLoaded &&
      other.snapshot.repository.branch == snapshot.repository.branch &&
      other.snapshot.repository.headOid == snapshot.repository.headOid &&
      other.snapshot.repository.isDetachedHead ==
          snapshot.repository.isDetachedHead &&
      other.snapshot.upstream == snapshot.upstream &&
      other.snapshot.ahead == snapshot.ahead &&
      other.snapshot.behind == snapshot.behind &&
      other.snapshot.clean == snapshot.clean &&
      other.snapshot.stashCount == snapshot.stashCount &&
      other.snapshot.commits.length == snapshot.commits.length &&
      other.snapshot.worktree.length == snapshot.worktree.length &&
      other.snapshot.commitsTruncated == snapshot.commitsTruncated &&
      other.visibleCommits.length == visibleCommits.length &&
      other.hasMoreCommits == hasMoreCommits &&
      other.loadingMore == loadingMore &&
      other.searchQuery == searchQuery &&
      other.selectedRef == selectedRef &&
      other.selectedCommitHash == selectedCommitHash &&
      other.selectedFilePath == selectedFilePath;

  @override
  int get hashCode => Object.hash(
    snapshot.repository.branch,
    snapshot.repository.headOid,
    snapshot.repository.isDetachedHead,
    snapshot.upstream,
    snapshot.ahead,
    snapshot.behind,
    snapshot.clean,
    snapshot.stashCount,
    snapshot.commits.length,
    snapshot.worktree.length,
    snapshot.commitsTruncated,
    visibleCommits.length,
    hasMoreCommits,
    loadingMore,
    searchQuery,
    selectedRef,
    selectedCommitHash,
    selectedFilePath,
  );

  @override
  String toString() =>
      'GitLoaded(branch: ${snapshot.repository.branch}, '
      'head: ${snapshot.repository.headOid?.substring(0, 7) ?? 'n/d'}, '
      'ahead: ${snapshot.ahead}, behind: ${snapshot.behind}, '
      'clean: ${snapshot.clean}, commits: ${visibleCommits.length}, '
      'worktree: ${snapshot.worktree.length}, '
      'searchQuery: $searchQuery, selectedCommit: $selectedCommitHash)';
}

/// A pasta vinculada existe mas nao e um repositorio Git.
class GitNotRepository extends GitState {
  const GitNotRepository();

  @override
  String toString() => 'GitNotRepository';
}

/// O repositorio descoberto esta acima da raiz vinculada: orienta o usuario
/// a abrir o diretorio real do repositorio.
class GitRepositoryOutsideRoot extends GitState {
  const GitRepositoryOutsideRoot({required this.topLevel});

  final String? topLevel;

  @override
  String toString() => 'GitRepositoryOutsideRoot(topLevel: $topLevel)';
}

/// Falha apresentavel do processo/parsing Git.
class GitFailure extends GitState {
  const GitFailure({required this.message});

  final String message;

  @override
  String toString() => 'GitFailure($message)';
}

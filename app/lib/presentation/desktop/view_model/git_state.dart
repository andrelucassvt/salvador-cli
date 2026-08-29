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

  final GitSnapshot? previous;

  @override
  String toString() =>
      'GitLoading(previous: ${previous == null ? 'nenhum' : 'snapshot'})';
}

/// Snapshot valido do repositorio na raiz vinculada.
class GitLoaded extends GitState {
  const GitLoaded({required this.snapshot});

  final GitSnapshot snapshot;

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
      other.snapshot.commitsTruncated == snapshot.commitsTruncated;

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
  );

  @override
  String toString() => 'GitLoaded(branch: ${snapshot.repository.branch}, '
      'head: ${snapshot.repository.headOid?.substring(0, 7) ?? 'n/d'}, '
      'ahead: ${snapshot.ahead}, behind: ${snapshot.behind}, '
      'clean: ${snapshot.clean}, commits: ${snapshot.commits.length}, '
      'worktree: ${snapshot.worktree.length})';
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

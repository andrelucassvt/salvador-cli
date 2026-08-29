import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

/// No do grafo: posicao de um commit em uma linha/lane.
@immutable
class GitGraphNode {
  const GitGraphNode({
    required this.commitHash,
    required this.index,
    required this.lane,
    this.isMerge = false,
    this.isHead = false,
  });

  final String commitHash;
  final int index;
  final int lane;
  final bool isMerge;
  final bool isHead;

  @override
  bool operator ==(Object other) =>
      other is GitGraphNode &&
      other.commitHash == commitHash &&
      other.index == index &&
      other.lane == lane &&
      other.isMerge == isMerge &&
      other.isHead == isHead;

  @override
  int get hashCode => Object.hash(commitHash, index, lane, isMerge, isHead);

  @override
  String toString() =>
      'GitGraphNode(${commitHash.substring(0, 7)} '
      'row: $index lane: $lane)';
}

/// Segmento do grafo: conexao desenhada entre a linha [row] e a linha
/// [row] + 1, saindo de [fromLane] e chegando em [toLane].
@immutable
class GitGraphSegment {
  const GitGraphSegment({
    required this.row,
    required this.fromLane,
    required this.toLane,
    this.isMerge = false,
  });

  final int row;
  final int fromLane;
  final int toLane;

  /// Conexao de merge (pai extra saindo do no), desenhada com cor distinta.
  final bool isMerge;

  bool get isVertical => fromLane == toLane;

  @override
  bool operator ==(Object other) =>
      other is GitGraphSegment &&
      other.row == row &&
      other.fromLane == fromLane &&
      other.toLane == toLane &&
      other.isMerge == isMerge;

  @override
  int get hashCode => Object.hash(row, fromLane, toLane, isMerge);

  @override
  String toString() =>
      'GitGraphSegment(row: $row $fromLane->$toLane'
      '${isMerge ? ' merge' : ''})';
}

/// Layout deterministico do grafo de commits, separado do painter para ser
/// testavel: converte a lista ordenada de commits (mais recente primeiro) em
/// nos por linha/lane e segmentos entre linhas.
@immutable
class GitGraphLayout {
  const GitGraphLayout({
    required this.nodes,
    required this.segments,
    required this.laneCount,
  });

  final List<GitGraphNode> nodes;
  final List<GitGraphSegment> segments;
  final int laneCount;

  static bool _listEquals(List<Object> a, List<Object> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is GitGraphLayout &&
      other.laneCount == laneCount &&
      _listEquals(other.nodes, nodes) &&
      _listEquals(other.segments, segments);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(nodes), Object.hashAll(segments), laneCount);

  /// Calcula lanes/nos/segmentos para [commits] na ordem de exibicao
  /// (mais recente primeiro). A ordem de lanes e deterministica para o
  /// mesmo conjunto de commits.
  ///
  /// Algoritmo classico de lanes por commit: cada lane aguarda um hash de
  /// commit; o primeiro pai continua a lane do commit, pais extras abrem
  /// novas lanes (conexoes de merge) e lanes que aguardavam um commit ja
  /// resolvido em outra lane convergem para ela.
  static GitGraphLayout calculate(List<GitCommit> commits) {
    final nodes = <GitGraphNode>[];
    final segments = <GitGraphSegment>[];
    var lanes = <String?>[];
    var maxLane = 0;

    void addSegment(int row, int fromLane, int toLane, {bool isMerge = false}) {
      segments.add(
        GitGraphSegment(
          row: row,
          fromLane: fromLane,
          toLane: toLane,
          isMerge: isMerge,
        ),
      );
      if (fromLane > maxLane) maxLane = fromLane;
      if (toLane > maxLane) maxLane = toLane;
    }

    for (var row = 0; row < commits.length; row++) {
      final commit = commits[row];
      final parentHashes = commit.parentHashes;

      // Lane do commit: a lane que esperava por ele, ou uma nova.
      var lane = lanes.indexOf(commit.hash);
      final isNewLane = lane < 0;
      if (isNewLane) lane = lanes.length;

      nodes.add(
        GitGraphNode(
          commitHash: commit.hash,
          index: row,
          lane: lane,
          isMerge: parentHashes.length > 1,
          isHead: row == 0,
        ),
      );
      if (lane > maxLane) maxLane = lane;

      // Proximas lanes: primeiro pai continua; pais extras abrem lanes.
      final next = List<String?>.of(lanes);
      if (isNewLane) {
        if (parentHashes.isNotEmpty) {
          next.add(parentHashes.first);
        }
      } else if (parentHashes.isNotEmpty) {
        next[lane] = parentHashes.first;
      } else {
        next[lane] = null;
      }

      if (parentHashes.isNotEmpty) {
        // Trunk: a lane do commit desce ate o primeiro pai.
        addSegment(row, lane, lane);
        // Pais extras: novas lanes saindo do no do merge.
        for (final parent in parentHashes.skip(1)) {
          next.add(parent);
          addSegment(row, lane, next.length - 1, isMerge: true);
        }
      }

      // Lanes que aguardavam o hash deste commit convergem para a lane dele.
      for (var index = 0; index < next.length; index++) {
        if (index != lane && next[index] == commit.hash) {
          next[index] = null;
          addSegment(row, index, lane);
        }
      }

      // Compactacao: lanes nulas saem e as seguintes deslocam para a
      // esquerda, registrando diagonais para o deslocamento.
      final compacted = <String?>[];
      for (var from = 0; from < next.length; from++) {
        final hash = next[from];
        if (hash == null) continue;
        if (compacted.length != from) {
          addSegment(row, from, compacted.length);
        }
        compacted.add(hash);
      }

      // Lanes que persistem na mesma posicao continuam verticais.
      for (var index = 0; index < compacted.length; index++) {
        if (index < lanes.length &&
            lanes[index] != null &&
            lanes[index] == compacted[index] &&
            !_isConnectedAt(segments, row, index)) {
          addSegment(row, index, index);
        }
      }

      lanes = compacted;
    }

    return GitGraphLayout(
      nodes: nodes,
      segments: segments,
      laneCount: commits.isEmpty ? 1 : maxLane + 1,
    );
  }

  static bool _isConnectedAt(
    List<GitGraphSegment> segments,
    int row,
    int lane,
  ) =>
      segments.any((segment) => segment.row == row && segment.fromLane == lane);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_graph_layout.dart';

void main() {
  GitCommit commit(String hash, {List<String> parents = const []}) => GitCommit(
    hash: hash,
    shortHash: hash.substring(0, 7),
    subject: hash,
    authorName: 'Test',
    authorEmail: 't@t.co',
    authorDate: DateTime(2026, 8, 29),
    parentHashes: parents,
  );

  final head = 'a000000000000000000000000000000000000000';
  final middle = 'b1111111111111111111111111111111111111111';
  final root = 'c2222222222222222222222222222222222222222';
  final side = 'd3333333333333333333333333333333333333333';
  final mergeBase = 'e44444444444444444444444444444444444444';

  void expectBounds(GitGraphLayout layout, int commitCount) {
    expect(layout.nodes, hasLength(commitCount));
    expect(layout.laneCount, greaterThanOrEqualTo(1));
    for (final node in layout.nodes) {
      expect(node.index, greaterThanOrEqualTo(0));
      expect(node.lane, greaterThanOrEqualTo(0));
      expect(node.lane, lessThan(layout.laneCount));
    }
    for (final segment in layout.segments) {
      expect(segment.row, greaterThanOrEqualTo(0));
      expect(segment.row, lessThan(commitCount));
      expect(segment.fromLane, greaterThanOrEqualTo(0));
      expect(segment.toLane, greaterThanOrEqualTo(0));
    }
  }

  group('GitGraphLayout.calculate', () {
    test('historico linear ocupa uma unica lane', () {
      final layout = GitGraphLayout.calculate([
        commit(head, parents: [middle]),
        commit(middle, parents: [root]),
        commit(root),
      ]);

      expect(layout.nodes.map((node) => node.lane), [0, 0, 0]);
      expect(layout.nodes.map((node) => node.index), [0, 1, 2]);
      expect(layout.laneCount, 1);
      expect(
        layout.segments.map((s) => '${s.row}:${s.fromLane}>${s.toLane}'),
        ['0:0>0', '1:0>0'],
        reason: 'trunks verticais entre os tres commits',
      );
      expectBounds(layout, 3);
    });

    test('bifurcacao cria nova lane para o segundo pai', () {
      final layout = GitGraphLayout.calculate([
        commit(head, parents: [middle, side]),
        commit(middle, parents: [mergeBase]),
        commit(side, parents: [mergeBase]),
        commit(mergeBase),
      ]);

      expect(layout.nodes.map((node) => node.lane), [0, 0, 1, 0]);
      expect(layout.laneCount, 2);
      expect(
        layout.segments.where((segment) => segment.isMerge),
        hasLength(1),
        reason: 'a bifurcacao do segundo pai e uma conexao de merge',
      );
      final merge = layout.segments.singleWhere((s) => s.isMerge);
      expect(merge.row, 0);
      expect(merge.fromLane, 0);
      expect(merge.toLane, 1);
      expectBounds(layout, 4);
    });

    test('merge de dois pais converge para a lane principal', () {
      final layout = GitGraphLayout.calculate([
        commit(head, parents: [middle, side]),
        commit(middle, parents: [mergeBase]),
        commit(side, parents: [mergeBase]),
        commit(mergeBase, parents: [root]),
        commit(root),
      ]);

      expect(layout.nodes.map((node) => node.lane), [0, 0, 1, 0, 0]);
      expect(
        layout.segments.any(
          (segment) => segment.fromLane == 1 && segment.toLane == 0,
        ),
        isTrue,
        reason: 'a lane lateral converge para a principal no commit base',
      );
      expectBounds(layout, 5);
    });

    test('refs no mesmo commit nao multiplicam nos', () {
      final layout = GitGraphLayout.calculate([
        commit(head, parents: [middle]),
        commit(middle, parents: [root]),
        commit(root),
      ]);

      expect(
        layout.nodes.where((node) => node.commitHash == middle),
        hasLength(1),
        reason: 'um commit com varios refs continua sendo um unico no',
      );
      expectBounds(layout, 3);
    });

    test('hash pai ausente por paginacao nao quebra o layout', () {
      final layout = GitGraphLayout.calculate([
        commit(head, parents: [middle]),
        commit(
          middle,
          parents: ['desconhecido00000000000000000000000000000000'],
        ),
      ]);

      expect(layout.nodes, hasLength(2));
      expectBounds(layout, 2);
    });

    test('ordem de lanes e deterministica para o mesmo conjunto', () {
      final commits = [
        commit(head, parents: [middle, side]),
        commit(middle, parents: [mergeBase]),
        commit(side, parents: [mergeBase]),
        commit(mergeBase),
      ];

      final first = GitGraphLayout.calculate(commits);
      final second = GitGraphLayout.calculate(commits);

      expect(second, equals(first));
    });

    test('lista vazia produz layout vazio com uma lane', () {
      final layout = GitGraphLayout.calculate(const []);

      expect(layout.nodes, isEmpty);
      expect(layout.segments, isEmpty);
      expect(layout.laneCount, 1);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/git_graph_layout.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/git_graph_painter.dart';

void main() {
  GitCommit commit(String hash, {List<String> parents = const []}) => GitCommit(
    hash: hash,
    shortHash: hash.substring(0, 7),
    subject: hash,
    authorName: 't',
    authorEmail: 't@t.co',
    authorDate: DateTime(2026, 8, 29),
    parentHashes: parents,
  );

  final commits = [
    commit(
      'a000000000000000000000000000000000000000',
      parents: ['b1111111111111111111111111111111111111111'],
    ),
    commit('b1111111111111111111111111111111111111111'),
  ];

  GitGraphPainter painter({GitGraphLayout? layout, Color? laneColor}) =>
      GitGraphPainter(
        layout: layout ?? GitGraphLayout.calculate(commits),
        row: 0,
        laneWidth: 22,
        rowHeight: 36,
        nodeRadius: 4.5,
        laneColor: laneColor ?? const Color(0xFFB8C4C9),
        mergeColor: const Color(0xFFF2A65A),
        nodeColor: const Color(0xFF147D92),
        headColor: const Color(0xFFED6A5A),
      );

  test('shouldRepaint retorna falso para dados equivalentes', () {
    final first = painter();
    final second = painter(layout: GitGraphLayout.calculate(commits));

    expect(first.shouldRepaint(second), isFalse);
  });

  test('shouldRepaint retorna verdadeiro quando o layout muda', () {
    final first = painter();
    final other = GitGraphLayout.calculate([
      commit(
        'a000000000000000000000000000000000000000',
        parents: [
          'b1111111111111111111111111111111111111111',
          'c2222222222222222222222222222222222222222',
        ],
      ),
      commit('b1111111111111111111111111111111111111111'),
      commit('c2222222222222222222222222222222222222222'),
    ]);

    expect(first.shouldRepaint(painter(layout: other)), isTrue);
  });

  test('shouldRepaint retorna verdadeiro quando as cores mudam', () {
    final first = painter();

    expect(
      first.shouldRepaint(painter(laneColor: const Color(0xFF000000))),
      isTrue,
    );
  });
}

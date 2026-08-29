import 'package:flutter/rendering.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/git_graph_layout.dart';

/// Desenha a fatia vertical de uma linha do grafo: o no do commit na linha
/// e os segmentos da transicao desta linha para a proxima. Sem `saveLayer`,
/// com `Paint`/`Path` criados dentro de `paint()`.
class GitGraphPainter extends CustomPainter {
  const GitGraphPainter({
    required this.layout,
    required this.row,
    required this.laneWidth,
    required this.rowHeight,
    required this.nodeRadius,
    required this.laneColor,
    required this.mergeColor,
    required this.nodeColor,
    required this.headColor,
  });

  final GitGraphLayout layout;
  final int row;
  final double laneWidth;
  final double rowHeight;
  final double nodeRadius;
  final Color laneColor;
  final Color mergeColor;
  final Color nodeColor;
  final Color headColor;

  @override
  void paint(Canvas canvas, Size size) {
    final node = row < layout.nodes.length ? layout.nodes[row] : null;
    final centerY = size.height / 2;

    for (final segment in layout.segments) {
      if (segment.row != row) continue;
      final paint = Paint()
        ..color = segment.isMerge ? mergeColor : laneColor
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final fromX = segment.fromLane * laneWidth + laneWidth / 2;
      final toX = segment.toLane * laneWidth + laneWidth / 2;
      final path = Path()
        ..moveTo(fromX, centerY)
        ..lineTo(fromX, centerY + rowHeight * 0.35)
        ..lineTo(toX, centerY + rowHeight * 0.65)
        ..lineTo(toX, centerY + rowHeight);
      canvas.drawPath(path, paint);
    }

    if (node == null) return;
    final nodeX = node.lane * laneWidth + laneWidth / 2;
    canvas.drawCircle(
      Offset(nodeX, centerY),
      nodeRadius,
      Paint()..color = node.isHead ? headColor : nodeColor,
    );
    if (node.isHead) {
      canvas.drawCircle(
        Offset(nodeX, centerY),
        nodeRadius,
        Paint()
          ..color = shell
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GitGraphPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.row != row ||
      oldDelegate.laneWidth != laneWidth ||
      oldDelegate.rowHeight != rowHeight ||
      oldDelegate.nodeRadius != nodeRadius ||
      oldDelegate.laneColor != laneColor ||
      oldDelegate.mergeColor != mergeColor ||
      oldDelegate.nodeColor != nodeColor ||
      oldDelegate.headColor != headColor;
}

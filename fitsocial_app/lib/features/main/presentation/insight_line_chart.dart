import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../domain/exercise_insights.dart';

/// A line through a movement's sessions, drawn by hand rather than with a
/// chart package — the same way the activity grid is drawn.
///
/// Points are spaced by date, not by index, so a month off shows as a gap.
/// Tapping or dragging picks the nearest session and [onSelect] reports it.
class InsightLineChart extends StatelessWidget {
  const InsightLineChart({
    required this.points,
    required this.selected,
    required this.onSelect,
    this.height = 180,
    super.key,
  });

  final List<InsightPoint> points;

  /// The index into [points] being read out, or null for the latest.
  final int? selected;
  final ValueChanged<int> onSelect;
  final double height;

  int _nearest(double dx, double width) {
    if (points.length < 2) return 0;
    final first = points.first.at.millisecondsSinceEpoch.toDouble();
    final last = points.last.at.millisecondsSinceEpoch.toDouble();
    final span = math.max(1.0, last - first);
    final target = first + (dx / width).clamp(0.0, 1.0) * span;
    var best = 0;
    var gap = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i].at.millisecondsSinceEpoch - target).abs();
      if (d < gap) {
        gap = d;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(Offset local) => onSelect(_nearest(local.dx, width));
        return Semantics(
          label: 'Progress chart, ${points.length} sessions',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => pick(d.localPosition),
            onHorizontalDragUpdate: (d) => pick(d.localPosition),
            child: CustomPaint(
              size: Size(width, height),
              painter: _LinePainter(
                points: points,
                selected: selected ?? points.length - 1,
                line: palette.brand,
                fill: palette.brand.withValues(alpha: 0.14),
                grid: palette.stroke,
                dot: palette.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.selected,
    required this.line,
    required this.fill,
    required this.grid,
    required this.dot,
  });

  final List<InsightPoint> points;
  final int selected;
  final Color line;
  final Color fill;
  final Color grid;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 10.0;
    const bottom = 10.0;
    final h = size.height - top - bottom;

    // Three faint rules, so a rise reads against something.
    final rule = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    if (points.isEmpty) return;

    final values = points.map((p) => p.value);
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    if (high - low < 1e-9) {
      // A flat line sits in the middle rather than on an edge.
      low -= 1;
      high += 1;
    }
    final first = points.first.at.millisecondsSinceEpoch.toDouble();
    final last = points.last.at.millisecondsSinceEpoch.toDouble();
    final span = last - first;

    Offset at(InsightPoint p) {
      final x = span <= 0
          ? size.width / 2
          : (p.at.millisecondsSinceEpoch - first) / span * size.width;
      final y = top + h - (p.value - low) / (high - low) * h;
      return Offset(x, y);
    }

    final offsets = points.map(at).toList();
    if (offsets.length > 1) {
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final o in offsets.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      final area = Path.from(path)
        ..lineTo(offsets.last.dx, size.height)
        ..lineTo(offsets.first.dx, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final dotPaint = Paint()..color = line;
    for (final o in offsets) {
      canvas.drawCircle(o, 3, dotPaint);
    }
    if (selected >= 0 && selected < offsets.length) {
      final o = offsets[selected];
      canvas.drawLine(
        Offset(o.dx, top),
        Offset(o.dx, size.height - bottom),
        Paint()
          ..color = grid
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(o, 6, Paint()..color = line);
      canvas.drawCircle(o, 3, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.line != line ||
      old.grid != grid;
}

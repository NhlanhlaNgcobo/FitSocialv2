import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/domain/app_models.dart';

/// A run's GPS trace drawn as a bare orange line, with no map under it.
///
/// [RunRouteMap] is the real thing and belongs on a post that has room for it,
/// but it is a platform view: a grid holding a dozen of them would spin up a
/// dozen Google Maps instances to render thumbnails the size of a stamp. This
/// paints the same shape from the route the post already carries — no tiles, no
/// network, no controller.
///
/// The line is scaled to fit and centred, keeping its proportions, so a route
/// reads as the shape the runner actually ran rather than being stretched to
/// the box.
class RouteSparkline extends StatelessWidget {
  const RouteSparkline({
    required this.route,
    this.strokeWidth = 2.5,
    this.padding = 4,
    super.key,
  });

  /// The trace, in order. Fewer than two fixes is not a route — callers should
  /// check [canDraw] and render something else.
  final List<RoutePoint> route;

  final double strokeWidth;

  /// Breathing room between the line and the edge of the box, so a route that
  /// fills its bounds doesn't touch the tile's border.
  final double padding;

  static bool canDraw(List<RoutePoint> route) => route.length >= 2;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomPaint(
      size: Size.infinite,
      painter: _RouteSparklinePainter(
        route: route,
        // The orange is the constant the full map keeps too, so a route looks
        // like the same route at both sizes.
        line: AppColors.orangeBright,
        // A wider, fainter pass under the line lifts it off the card without
        // needing a shadow. Light needs less of it — a wash on cream muddies
        // where it would glow on black.
        halo: AppColors.orangeBright
            .withValues(alpha: palette.isDark ? 0.22 : 0.14),
        start: palette.success,
        padding: padding,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

class _RouteSparklinePainter extends CustomPainter {
  const _RouteSparklinePainter({
    required this.route,
    required this.line,
    required this.halo,
    required this.start,
    required this.padding,
    required this.strokeWidth,
  });

  final List<RoutePoint> route;
  final Color line;
  final Color halo;
  final Color start;
  final double padding;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;

    final points = _project(size);
    if (points.isEmpty) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    stroke
      ..color = halo
      ..strokeWidth = strokeWidth * 3;
    canvas.drawPath(path, stroke);

    stroke
      ..color = line
      ..strokeWidth = strokeWidth;
    canvas.drawPath(path, stroke);

    // Where the run began and where it ended. Two dots is all the legend a
    // thumbnail can carry, and on a loop they land on top of each other, which
    // is itself readable.
    final dot = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(points.first, strokeWidth * 1.3, dot..color = start);
    canvas.drawCircle(points.last, strokeWidth * 1.3, dot..color = line);
  }

  /// The trace mapped into [size], preserving its aspect.
  ///
  /// Returns empty when the box is too small to draw anything into, rather than
  /// projecting onto negative bounds.
  List<Offset> _project(Size size) {
    final boxWidth = size.width - padding * 2;
    final boxHeight = size.height - padding * 2;
    if (boxWidth <= 0 || boxHeight <= 0) return const [];

    var minLat = route.first.latitude;
    var maxLat = minLat;
    var minLng = route.first.longitude;
    var maxLng = minLng;
    for (final point in route) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    // A degree of longitude covers less ground the further from the equator you
    // run. Without this the same loop comes out visibly wider in Oslo than in
    // Nairobi.
    final lngScale = math.cos((minLat + maxLat) / 2 * math.pi / 180).abs();

    // Floored, so an out-and-back along one street — zero span on the other
    // axis — scales by the axis that does have extent instead of dividing by
    // zero.
    const minSpan = 1e-7;
    final spanX = math.max((maxLng - minLng) * lngScale, minSpan);
    final spanY = math.max(maxLat - minLat, minSpan);

    final scale = math.min(boxWidth / spanX, boxHeight / spanY);
    final originX = (size.width - spanX * scale) / 2;
    final originY = (size.height - spanY * scale) / 2;

    return [
      for (final point in route)
        Offset(
          originX + (point.longitude - minLng) * lngScale * scale,
          // Latitude grows north, y grows down.
          originY + (maxLat - point.latitude) * scale,
        ),
    ];
  }

  @override
  bool shouldRepaint(_RouteSparklinePainter old) =>
      old.route != route ||
      old.line != line ||
      old.halo != halo ||
      old.start != start ||
      old.padding != padding ||
      old.strokeWidth != strokeWidth;
}

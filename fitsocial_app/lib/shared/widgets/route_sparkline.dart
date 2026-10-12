import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';
import '../../features/main/domain/app_models.dart';
import 'route_smoothing.dart';
import 'run_route_geometry.dart';

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
/// the box. [placement] then moves and resizes it from there, for a runner who
/// dragged it off their face.
///
/// The trace is simplified and smoothed before it is drawn (see
/// route_smoothing.dart), so GPS jitter never reads as a shaky line.
class RouteSparkline extends StatelessWidget {
  const RouteSparkline({
    required this.route,
    this.strokeWidth = 2.5,
    this.padding = 4,
    this.onMedia = false,
    this.colourByPace = false,
    this.placement = RoutePlacement.centred,
    super.key,
  });

  /// The trace, in order. Fewer than two fixes is not a route — callers should
  /// check [canDraw] and render something else.
  final List<RoutePoint> route;

  final double strokeWidth;

  /// Breathing room between the line and the edge of the box, so a route that
  /// fills its bounds doesn't touch the tile's border.
  final double padding;

  /// Whether the line is being drawn over a user's photo rather than over an
  /// app surface.
  ///
  /// A photo is neither light nor dark — the same run can cross a white sky and
  /// black tarmac in one stride — so the palette's answer is no answer at all
  /// there. This lays a soft black pass under the line to carry it across the
  /// bright parts and widens the glow to hold it against the dark ones.
  final bool onMedia;

  /// Whether to colour each stretch by how fast it was run, on the same ramp
  /// the full map uses — deep red where the runner eased off, yellow where they
  /// pushed. Falls back to the plain line when the route has no timings, or
  /// was run so evenly there is nothing to show.
  final bool colourByPace;

  /// Where the runner moved the line to, and how big they made it.
  final RoutePlacement placement;

  static bool canDraw(List<RoutePoint> route) => route.length >= 2;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomPaint(
      size: Size.infinite,
      painter: _RouteSparklinePainter(
        route: route,
        // The orange is the constant the full map keeps too, so a route looks
        // like the same route at both sizes — fixed on a photo, and following
        // the theme's own weight on a card.
        line: onMedia ? AppColors.orangeBright : palette.brand,
        // A wider, fainter pass under the line lifts it off the card without
        // needing a shadow. Light needs less of it — a wash on cream muddies
        // where it would glow on black.
        halo: (onMedia ? AppColors.orangeBright : palette.brand).withValues(
          alpha: onMedia
              ? 0.34
              : palette.isDark
                  ? 0.22
                  : 0.14,
        ),
        // Fixed on a photo, for the same reason the halo is: a green tuned for
        // the light theme is the wrong green on somebody's sunset.
        start: onMedia ? const Color(0xFF31C46C) : palette.success,
        shadow: onMedia ? const Color(0x59050505) : null,
        padding: padding,
        strokeWidth: strokeWidth,
        pace: colourByPace ? _paceSpansFor(route) : null,
        placement: placement,
      ),
    );
  }
}

/// Pace colouring, worked out once per route rather than once per frame: a
/// route list is immutable once it is on a post, so its identity is its key.
final _paceCache = Expando<_PaceEntry>('routePace');

class _PaceEntry {
  const _PaceEntry(this.spans);
  final List<PaceSpan>? spans;
}

List<PaceSpan>? _paceSpansFor(List<RoutePoint> route) {
  if (route.length < 3) return null;
  final cached = _paceCache[route];
  if (cached != null) return cached.spans;
  final spans = paceSpans(
    [for (final point in route) LatLng(point.latitude, point.longitude)],
    RoutePoint.secondsOf(route),
  );
  _paceCache[route] = _PaceEntry(spans);
  return spans;
}

class _RouteSparklinePainter extends CustomPainter {
  const _RouteSparklinePainter({
    required this.route,
    required this.line,
    required this.halo,
    required this.start,
    required this.shadow,
    required this.padding,
    required this.strokeWidth,
    required this.pace,
    required this.placement,
  });

  final List<RoutePoint> route;
  final Color line;
  final Color halo;
  final Color start;

  /// Laid under everything else when the line is over a photo. Null on an app
  /// surface, where the halo alone is enough.
  final Color? shadow;
  final double padding;
  final double strokeWidth;

  /// The route split into stretches by speed, or null for one plain line.
  final List<PaceSpan>? pace;
  final RoutePlacement placement;

  @override
  void paint(Canvas canvas, Size size) {
    if (route.length < 2) return;

    final points = _place(_project(size), size);
    if (points.isEmpty) return;

    // About a third of the stroke: enough to iron out the zigzag a phone adds
    // to a straight road, never enough to cut a real corner.
    final tolerance = math.max(0.6, strokeWidth * 0.35);

    // One path per stretch of pace, each starting where the last one ended so
    // the line is unbroken. Without pace colouring that is a single stretch.
    final spans = pace;
    final pieces = <({Path path, Color color})>[];
    if (spans != null && spans.isNotEmpty) {
      for (final span in spans) {
        final end = math.min(span.start + span.points.length, points.length);
        if (end - span.start < 2) continue;
        final stretch = points.sublist(span.start, end);
        pieces.add((
          path: simplifiedSmoothPath(stretch, tolerance),
          color: paceColour(span.band),
        ));
      }
    }
    if (pieces.isEmpty) {
      pieces.add((path: simplifiedSmoothPath(points, tolerance), color: line));
    }

    final path = Path();
    for (final piece in pieces) {
      path.addPath(piece.path, Offset.zero);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shadowColor = shadow;
    if (shadowColor != null) {
      stroke
        ..color = shadowColor
        ..strokeWidth = strokeWidth * 4
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth);
      canvas.drawPath(path, stroke);
      stroke.maskFilter = null;
    }

    stroke
      ..color = halo
      ..strokeWidth = strokeWidth * 3;
    canvas.drawPath(path, stroke);

    stroke.strokeWidth = strokeWidth;
    for (final piece in pieces) {
      canvas.drawPath(piece.path, stroke..color = piece.color);
    }

    // Where the run began and where it ended. Two dots is all the legend a
    // thumbnail can carry, and on a loop they land on top of each other, which
    // is itself readable.
    final dot = Paint()..style = PaintingStyle.fill;
    canvas.drawCircle(points.first, strokeWidth * 1.3, dot..color = start);
    canvas.drawCircle(
      points.last,
      strokeWidth * 1.3,
      dot..color = pieces.last.color,
    );
  }

  /// [points] moved and resized the way the runner placed them: scaled about
  /// the middle of the box, then shifted by a fraction of its size. The stroke
  /// is not scaled with it — a bigger route is a bigger shape, not a fatter
  /// pen.
  List<Offset> _place(List<Offset> points, Size size) {
    if (points.isEmpty || placement.isCentred) return points;
    final held = placement.clamped();
    final centre = size.center(Offset.zero);
    final shift = Offset(held.dx * size.width, held.dy * size.height);
    return [
      for (final point in points)
        centre + (point - centre) * held.scale + shift,
    ];
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
      old.shadow != shadow ||
      old.padding != padding ||
      old.strokeWidth != strokeWidth ||
      old.pace != pace ||
      old.placement != placement;
}

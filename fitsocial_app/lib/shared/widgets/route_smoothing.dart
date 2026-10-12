import 'dart:ui';

/// Turns a projected GPS trace into a line that reads as drawn rather than
/// plotted.
///
/// Two passes, both in screen space so they scale with the card rather than
/// with the run:
///
/// 1. [simplifyIndices] drops fixes that sit within a pixel or so of the line
///    between their neighbours — the jitter a phone's GPS adds to a straight
///    road, which at card size reads as a shaky hand.
/// 2. [smoothPath] draws what is left as a chain of quadratic curves through
///    the midpoints of each segment, so every corner is rounded the way a
///    runner actually rounds it.
///
/// Kept apart from the painter so both can be tested without a canvas.

/// The indices of [points] worth keeping, in order: always the first and the
/// last, plus every point that strays more than [tolerance] from the straight
/// line its neighbours would draw without it (Ramer–Douglas–Peucker).
///
/// Iterative rather than recursive, because a long run is thousands of fixes
/// and a worst-case trace would recurse once per fix.
List<int> simplifyIndices(List<Offset> points, double tolerance) {
  final count = points.length;
  if (count <= 2 || tolerance <= 0) {
    return List<int>.generate(count, (i) => i);
  }

  final keep = List<bool>.filled(count, false);
  keep[0] = true;
  keep[count - 1] = true;
  final toleranceSquared = tolerance * tolerance;

  final stack = <(int, int)>[(0, count - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    if (last - first < 2) continue;

    var farthest = -1;
    var farthestDistance = toleranceSquared;
    for (var i = first + 1; i < last; i++) {
      final distance =
          _segmentDistanceSquared(points[i], points[first], points[last]);
      if (distance > farthestDistance) {
        farthest = i;
        farthestDistance = distance;
      }
    }
    if (farthest < 0) continue;

    keep[farthest] = true;
    stack
      ..add((first, farthest))
      ..add((farthest, last));
  }

  return [
    for (var i = 0; i < count; i++)
      if (keep[i]) i,
  ];
}

/// Squared distance from [p] to the segment [a]–[b].
double _segmentDistanceSquared(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distanceSquared;
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final nearest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return (p - nearest).distanceSquared;
}

/// [points] as one smooth path that still starts on the first point and ends
/// on the last, so the start and finish dots sit exactly on the line.
///
/// Each interior point becomes the control point of a quadratic curve between
/// the midpoints of the segments either side of it. Two points are a straight
/// line; fewer is an empty path.
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  for (var i = 1; i < points.length - 1; i++) {
    final control = points[i];
    final next = points[i + 1];
    path.quadraticBezierTo(
      control.dx,
      control.dy,
      (control.dx + next.dx) / 2,
      (control.dy + next.dy) / 2,
    );
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// [points] simplified to within [tolerance] and then smoothed — the line the
/// run card actually draws.
Path simplifiedSmoothPath(List<Offset> points, double tolerance) {
  final kept = simplifyIndices(points, tolerance);
  return smoothPath([for (final i in kept) points[i]]);
}

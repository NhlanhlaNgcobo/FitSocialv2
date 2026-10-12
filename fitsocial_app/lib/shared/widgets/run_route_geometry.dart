import 'dart:math' as math;
import 'dart:ui' show Color, lerpDouble;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The arithmetic behind a run map: distances along a route, where its
/// kilometres fall, which way the runner is facing, and how fast each stretch
/// was. Kept apart from the widget so it can be tested without a map.

const _earthRadiusMeters = 6371000.0;

double _rad(double degrees) => degrees * math.pi / 180;

/// Great-circle distance between two fixes, in metres.
double distanceMeters(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.sqrt(h.toDouble()));
}

/// Compass bearing from [from] to [to], 0–360 with north at 0.
double bearingDegrees(LatLng from, LatLng to) {
  final lat1 = _rad(from.latitude);
  final lat2 = _rad(to.latitude);
  final dLng = _rad(to.longitude - from.longitude);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Which way the runner is heading at the end of [route], measured over the
/// last [lookBackMeters] so GPS jitter between two close fixes cannot spin the
/// camera. Null until they have covered that much ground.
double? headingAt(List<LatLng> route, {double lookBackMeters = 20}) {
  if (route.length < 2) return null;
  final last = route.last;
  for (var i = route.length - 2; i >= 0; i--) {
    if (distanceMeters(route[i], last) >= lookBackMeters) {
      return bearingDegrees(route[i], last);
    }
  }
  return null;
}

/// A whole kilometre passed along the route, where, and the index of the first
/// fix after it — so a replay knows when it has been reached.
typedef KmSplit = ({int km, LatLng at, int index});

/// Every whole kilometre along [route], placed by interpolating between the
/// two fixes either side of it.
List<KmSplit> kmSplits(List<LatLng> route) {
  final splits = <KmSplit>[];
  var travelled = 0.0;
  for (var i = 1; i < route.length; i++) {
    final step = distanceMeters(route[i - 1], route[i]);
    if (step <= 0) continue;
    while (travelled + step >= (splits.length + 1) * 1000) {
      final into = ((splits.length + 1) * 1000 - travelled) / step;
      splits.add((
        km: splits.length + 1,
        at: lerpLatLng(route[i - 1], route[i], into),
        index: i,
      ));
    }
    travelled += step;
  }
  return splits;
}

LatLng lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
      lerpDouble(a.latitude, b.latitude, t)!,
      lerpDouble(a.longitude, b.longitude, t)!,
    );

/// The first [progress] (0–1) of [route], ending on a point interpolated
/// between fixes so a replay glides instead of jumping fix to fix.
List<LatLng> routePrefix(List<LatLng> route, double progress) {
  if (route.length < 2 || progress >= 1) return route;
  if (progress <= 0) return [route.first];
  final position = progress * (route.length - 1);
  final whole = position.floor();
  return [
    ...route.take(whole + 1),
    lerpLatLng(route[whole], route[whole + 1], position - whole),
  ];
}

/// A stretch of route run at one speed band, ready to draw as one line, and
/// the index in the route of its first point.
typedef PaceSpan = ({List<LatLng> points, int band, int start});

/// How many colours the pace ramp has.
const paceBands = 6;

/// Slow to fast: deep red, through the brand orange, to yellow.
const _paceRamp = <Color>[
  Color(0xFFC81E1E),
  Color(0xFFE2401C),
  Color(0xFFF2601A),
  Color(0xFFFF7E1A),
  Color(0xFFFFA51F),
  Color(0xFFFFD23F),
];

Color paceColour(int band) => _paceRamp[band.clamp(0, paceBands - 1)];

/// A gap between two fixes longer than this is a pause — a traffic light, a
/// tap on pause — not a stretch run slowly, so it carries no pace.
const _pauseGapSeconds = 30.0;

/// Splits [route] into runs of segments sharing a speed band, judged against
/// the run's own spread of speeds so every run uses the whole ramp: an easy
/// jog still shows where it picked up.
///
/// [seconds] holds each fix's time since the start. Null when the route has no
/// usable times — mismatched lengths, too few moving segments, or a run held so
/// even there is nothing to colour.
List<PaceSpan>? paceSpans(List<LatLng> route, List<double>? seconds) {
  if (seconds == null || seconds.length != route.length || route.length < 3) {
    return null;
  }

  final n = route.length - 1;
  final meters =
      List<double>.generate(n, (i) => distanceMeters(route[i], route[i + 1]));
  final dts = List<double>.generate(n, (i) => seconds[i + 1] - seconds[i]);
  bool moving(int i) => dts[i] > 0 && dts[i] <= _pauseGapSeconds;

  // Each segment's speed is smoothed over about 100 m of route around it, so a
  // single noisy fix does not paint a red fleck into a steady run.
  final speeds = List<double?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    if (!moving(i)) continue;
    var d = meters[i];
    var t = dts[i];
    var left = i - 1;
    var right = i + 1;
    while (d < 100 && (left >= 0 || right < n)) {
      if (left >= 0) {
        if (moving(left)) {
          d += meters[left];
          t += dts[left];
        }
        left--;
      }
      if (right < n) {
        if (moving(right)) {
          d += meters[right];
          t += dts[right];
        }
        right++;
      }
    }
    speeds[i] = d / t;
  }

  final known = speeds.whereType<double>().toList()..sort();
  if (known.length < 4) return null;
  final slow = known[(known.length * 0.1).floor()];
  final fast = known[(known.length * 0.9).floor().clamp(0, known.length - 1)];
  // Under about 5% between the slow and fast ends, the colours would only be
  // drawing GPS noise.
  if (slow <= 0 || fast / slow < 1.05) return null;

  int bandOf(double speed) =>
      (((speed - slow) / (fast - slow)).clamp(0.0, 1.0) * (paceBands - 1))
          .round();

  // A paused segment takes its neighbour's band rather than breaking the line.
  final bands = List<int>.filled(n, paceBands ~/ 2);
  int? previous;
  for (var i = 0; i < n; i++) {
    final speed = speeds[i];
    if (speed != null) previous = bandOf(speed);
    bands[i] = previous ?? bands[i];
  }
  final firstKnown = speeds.indexWhere((s) => s != null);
  for (var i = 0; i < firstKnown; i++) {
    bands[i] = bandOf(speeds[firstKnown]!);
  }

  final spans = <PaceSpan>[];
  var start = 0;
  for (var i = 1; i <= n; i++) {
    if (i == n || bands[i] != bands[start]) {
      spans.add((
        points: route.sublist(start, i + 1),
        band: bands[start],
        start: start,
      ));
      start = i;
    }
  }
  return spans;
}

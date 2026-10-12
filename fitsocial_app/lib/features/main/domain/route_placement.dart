import 'package:flutter/foundation.dart';

/// Where the runner put their route line on the photo behind a run card, and
/// how big they made it.
///
/// Stored as fractions rather than pixels, because the same card is drawn at
/// several widths — the finish sheet's preview, the feed, the post screen and
/// the 1080 px export — and the line has to land on the same part of the photo
/// in all of them.
@immutable
class RoutePlacement {
  const RoutePlacement({this.dx = 0, this.dy = 0, this.scale = 1});

  /// Where the line sits with nobody having moved it: centred, fitted to the
  /// card. Every run shared before placement existed reads as this.
  static const centred = RoutePlacement();

  /// How small the line may be pinched. Below this a route stops reading as a
  /// shape and turns into a squiggle.
  static const double minScale = 0.35;

  /// How large it may be spread. Past this most of the line is off the card.
  static const double maxScale = 2.5;

  /// How far the line's centre may be dragged from the card's centre, as a
  /// fraction of the box it is drawn in. Half is the edge: the line can hang
  /// off a side, but never vanish entirely.
  static const double maxOffset = 0.5;

  /// Horizontal offset of the line's centre from the card's centre, as a
  /// fraction of the card's width. Positive is right.
  final double dx;

  /// Vertical offset of the line's centre, as a fraction of the card's height.
  /// Positive is down.
  final double dy;

  /// Size relative to the fitted line. 1 fills the card the way it always has.
  final double scale;

  /// Whether this is, give or take a rounding error, the default. A placement
  /// nudged back to the middle by hand is the default, and is not worth
  /// writing to the post.
  bool get isCentred =>
      dx.abs() < 0.005 && dy.abs() < 0.005 && (scale - 1).abs() < 0.01;

  /// The same placement held inside the limits above.
  RoutePlacement clamped() => RoutePlacement(
        dx: dx.clamp(-maxOffset, maxOffset).toDouble(),
        dy: dy.clamp(-maxOffset, maxOffset).toDouble(),
        scale: scale.clamp(minScale, maxScale).toDouble(),
      );

  RoutePlacement copyWith({double? dx, double? dy, double? scale}) =>
      RoutePlacement(
        dx: dx ?? this.dx,
        dy: dy ?? this.dy,
        scale: scale ?? this.scale,
      );

  /// Firestore representation, or null for the default — a post the runner
  /// never adjusted is written exactly as every run before this existed.
  Map<String, double>? toMap() {
    if (isCentred) return null;
    final held = clamped();
    double round(double value) => (value * 10000).roundToDouble() / 10000;
    return {
      'x': round(held.dx),
      'y': round(held.dy),
      's': round(held.scale),
    };
  }

  /// Reads a stored placement, falling back to [centred] for anything missing
  /// or malformed: a bad value moves the line back to the middle, it never
  /// takes the card down.
  static RoutePlacement fromMap(Object? value) {
    if (value is! Map) return centred;
    double? read(String key) {
      final raw = value[key];
      if (raw is! num) return null;
      final number = raw.toDouble();
      return number.isFinite ? number : null;
    }

    return RoutePlacement(
      dx: read('x') ?? 0,
      dy: read('y') ?? 0,
      scale: read('s') ?? 1,
    ).clamped();
  }

  @override
  bool operator ==(Object other) =>
      other is RoutePlacement &&
      other.dx == dx &&
      other.dy == dy &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(dx, dy, scale);

  @override
  String toString() => 'RoutePlacement(dx: $dx, dy: $dy, scale: $scale)';
}

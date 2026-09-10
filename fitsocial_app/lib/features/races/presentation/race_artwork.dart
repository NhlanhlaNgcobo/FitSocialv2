import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../shared/widgets/app_photo.dart';
import '../domain/race_models.dart';

/// Generated cover art for a race that has no photograph.
///
/// Most of the calendar will never have a photograph. Club league races are
/// organised off a WhatsApp group and a fixture PDF; there is no poster, no
/// press kit and no entry page to take a banner from. A calendar that showed a
/// picture for the commercial third and a grey rectangle for the rest would
/// read as broken rather than as sparse — and it would quietly rank the small
/// club races below the sponsored ones.
///
/// So every race gets art, derived from the race itself: the hue from its name,
/// the route line from its distances, the terrain from its tags. Two races never
/// look alike, the same race looks the same on every device and every launch,
/// and nothing is fetched over the network to draw it.
class RaceArtwork extends StatelessWidget {
  const RaceArtwork({required this.event, this.showDistance = true, super.key});

  final RaceEvent event;

  /// Whether the longest distance is drawn across the art. Suppressed on very
  /// small renditions, where it would be unreadable.
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return CustomPaint(
      painter: _RaceArtworkPainter(
        seed: _seedOf(event),
        profile: _profileOf(event),
        label: showDistance ? _distanceLabel(event) : null,
        isDark: palette.isDark,
        brand: palette.brand,
      ),
      isComplex: true,
      willChange: false,
      size: Size.infinite,
    );
  }

  /// A stable hash of the race's identity.
  ///
  /// FNV-1a rather than [String.hashCode]: Dart makes no promise that string
  /// hashes are stable across runs or platforms, and art that changed colour
  /// when the app restarted would be worse than no art.
  static int _seedOf(RaceEvent event) {
    const offset = 0x811c9dc5;
    const prime = 0x01000193;
    var hash = offset;
    for (final unit in '${event.name}|${event.venue.city}'.codeUnits) {
      hash = ((hash ^ unit) * prime) & 0xffffffff;
    }
    return hash;
  }

  /// How rugged the route line should look.
  ///
  /// Trail and cross-country races get a jagged profile, road races a smooth
  /// one. It is the single visual cue that separates the two at a glance in a
  /// list, which is what a runner scanning for a trail race actually wants.
  static _Profile _profileOf(RaceEvent event) {
    if (event.tags.contains(RaceTag.trail)) return _Profile.trail;
    if (event.tags.contains(RaceTag.crossCountry)) return _Profile.trail;
    return _Profile.road;
  }

  static String? _distanceLabel(RaceEvent event) {
    if (event.distances.isEmpty) return null;
    // The longest distance is the one that characterises a race: nobody calls
    // an event with 5/10/21.1/42.2 km "a 5 km".
    final longest = event.distances
        .map((distance) => distance.kilometres)
        .reduce((a, b) => a > b ? a : b);
    if (longest == longest.roundToDouble()) return '${longest.round()}K';
    return '${longest.toStringAsFixed(1)}K';
  }
}

enum _Profile { road, trail }

class _RaceArtworkPainter extends CustomPainter {
  _RaceArtworkPainter({
    required this.seed,
    required this.profile,
    required this.label,
    required this.isDark,
    required this.brand,
  });

  final int seed;
  final _Profile profile;
  final String? label;
  final bool isDark;
  final Color brand;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final random = math.Random(seed);
    final rect = Offset.zero & size;

    // One hue per race, spun off the seed. Saturation and lightness are pinned
    // rather than randomised so every cover sits at the same visual weight —
    // a calendar where some rows glare and others recede is harder to scan,
    // not more interesting.
    final hue = (seed % 360).toDouble();
    final base =
        HSLColor.fromAHSL(1, hue, 0.42, isDark ? 0.22 : 0.72).toColor();
    final far = HSLColor.fromAHSL(
      1,
      (hue + 38) % 360,
      0.46,
      isDark ? 0.11 : 0.60,
    ).toColor();

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          [base, far],
        ),
    );

    _paintRidges(canvas, size, random);
    _paintRoute(canvas, size, random);
    if (label != null) _paintLabel(canvas, size, label!);
  }

  /// Two soft hills behind the route, for depth.
  void _paintRidges(Canvas canvas, Size size, math.Random random) {
    for (var layer = 0; layer < 2; layer++) {
      final baseline = size.height * (0.62 + layer * 0.16);
      final amplitude = size.height * (0.17 - layer * 0.05);
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, baseline);

      final steps = profile == _Profile.trail ? 7 : 4;
      for (var i = 1; i <= steps; i++) {
        final x = size.width * i / steps;
        final wobble = (random.nextDouble() - 0.5) * amplitude;
        final y = baseline + wobble;
        if (profile == _Profile.trail) {
          path.lineTo(x, y);
        } else {
          // Road profiles curve; trail profiles break. Same data, different
          // grammar.
          final prevX = size.width * (i - 1) / steps;
          path.quadraticBezierTo((prevX + x) / 2, y - amplitude * 0.4, x, y);
        }
      }
      path.lineTo(size.width, size.height);
      path.close();

      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: isDark ? 0.20 : 0.09),
      );
    }
  }

  /// The route line — the one brand-coloured element.
  void _paintRoute(Canvas canvas, Size size, math.Random random) {
    final path = Path();
    final y0 = size.height * (0.30 + random.nextDouble() * 0.18);
    path.moveTo(-size.width * 0.05, y0);

    final steps = profile == _Profile.trail ? 6 : 3;
    var x = -size.width * 0.05;
    var y = y0;
    for (var i = 1; i <= steps; i++) {
      final nx = size.width * 1.05 * i / steps;
      final ny = size.height *
          (0.22 +
              random.nextDouble() * (profile == _Profile.trail ? 0.42 : 0.26));
      if (profile == _Profile.trail) {
        path.lineTo(nx, ny);
      } else {
        path.cubicTo(x + (nx - x) / 2, y, x + (nx - x) / 2, ny, nx, ny);
      }
      x = nx;
      y = ny;
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, size.height * 0.022)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = brand.withValues(alpha: 0.85),
    );
  }

  /// The headline distance, set large and faint behind everything.
  void _paintLabel(Canvas canvas, Size size, String text) {
    // Scaled to the art rather than fixed, so the same painter serves a 56 px
    // thumbnail and a full-width hero without a second code path.
    final fontSize = size.height * 0.42;
    if (fontSize < 11) return;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          color: Colors.white.withValues(alpha: isDark ? 0.13 : 0.22),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(
        size.width - painter.width - size.width * 0.04,
        size.height - painter.height - size.height * 0.06,
      ),
    );
  }

  @override
  bool shouldRepaint(_RaceArtworkPainter old) =>
      old.seed != seed ||
      old.profile != profile ||
      old.label != label ||
      old.isDark != isDark ||
      old.brand != brand;
}

/// A race's cover: its photograph if it has one, its generated art otherwise.
///
/// The fallback also catches a photograph that fails to load. Entry links and
/// their images live on somebody else's CDN, and a URL that 404s a month from
/// now should degrade to the generated cover rather than to a broken-image box.
class RaceCover extends StatelessWidget {
  const RaceCover({
    required this.event,
    this.showDistance = true,
    super.key,
  });

  final RaceEvent event;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final url = event.imageUrl;
    final fallback = RaceArtwork(event: event, showDistance: showDistance);
    if (url == null || url.isEmpty) return fallback;

    return Image(
      image: appPhoto(url),
      fit: BoxFit.cover,
      // The generated art stands in while the photograph downloads, so a slow
      // connection shows the race rather than an empty grey band.
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

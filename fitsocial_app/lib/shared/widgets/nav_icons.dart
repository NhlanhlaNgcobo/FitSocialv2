import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// The five destinations of the floating nav, drawn as paths rather than pulled
/// from the Material icon font.
///
/// Two reasons they are hand-drawn:
///
///  * **Selection can morph.** A font glyph can only be swapped for a different
///    glyph, which is why the bar used to cross-fade `home_outlined` into
///    `home_rounded` — two drawings dissolving through each other. Here the
///    outline and the solid are the *same* path, and selecting animates a fill
///    alpha and a stroke weight over it, so the mark thickens into place
///    instead of blinking.
///  * **They can carry the brand.** [NavGlyph.activity] is the logo's pulse
///    wave, not a checkmark; [NavGlyph.explore] is a swept compass needle, not
///    a magnifier. Both are drawn on the same 24-unit grid at the same weight
///    as the rest, which no mix of stock icons gives you.
enum NavGlyph {
  /// A gabled house with an arched doorway. Selected, the body goes solid and
  /// the doorway is knocked *out* of it — on glass, that hole shows the blurred
  /// page through the mark.
  home,

  /// A compass needle swept about its waist, inside its bezel.
  explore,

  /// The plus on the brand disc. Drawn here purely so its weight matches the
  /// family; it has no unselected state, since the disc is always lit.
  create,

  /// A single heartbeat across the box — the app's own pulse wave. Selected,
  /// a bulb lands on the peak.
  activity,

  /// Head and shoulders.
  profile,
}

/// A [NavGlyph] rendered at [size], morphing between unselected and selected.
class NavIcon extends StatelessWidget {
  const NavIcon({
    required this.glyph,
    required this.selected,
    required this.color,
    required this.activeColor,
    this.size = 26,
    super.key,
  });

  final NavGlyph glyph;
  final bool selected;

  /// Resting colour, unselected.
  final Color color;

  /// Colour at full selection. The paint lerps between the two with the morph,
  /// so the colour arrives in step with the fill rather than ahead of it.
  final Color activeColor;

  final double size;

  static const Duration _morph = Duration(milliseconds: 260);

  /// How far the mark swells as it passes through the middle of the morph.
  static const double _swell = 0.09;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // No `begin`, so the first build lands on its end value — a tab that is
      // already selected when the bar appears must not play the morph.
      tween: Tween<double>(end: selected ? 1 : 0),
      duration: _morph,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return Transform.scale(
          // Half a sine: peaks mid-morph and returns to exactly 1, so the tap
          // reads as the mark being pressed and springing back rather than as
          // the selected tab simply being drawn larger.
          scale: 1 + (_swell * math.sin(math.pi * t)),
          child: CustomPaint(
            size: Size.square(size),
            isComplex: false,
            painter: _GlyphPainter(
              glyph: glyph,
              t: t,
              color: Color.lerp(color, activeColor, t)!,
            ),
          ),
        );
      },
    );
  }
}

/// Draws a [NavGlyph] on a 24-unit grid, at morph position [t] (0 unselected,
/// 1 selected).
///
/// Every mark is built the same way: one silhouette path, stroked at all times
/// and filled by [t]. Keeping the geometry identical across the two states is
/// the whole point — nothing moves as a tab is selected except weight and ink.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.glyph,
    required this.t,
    required this.color,
  });

  final NavGlyph glyph;
  final double t;
  final Color color;

  /// The design grid everything below is drawn in.
  static const double _grid = 24;

  /// Selected marks carry slightly more weight, so the tab still reads as
  /// chosen at a glance in the themes where fill alone is subtle.
  static const double _weightRest = 1.9;
  static const double _weightActive = 2.15;

  Paint _stroke({double? width, double alpha = 1}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width ?? lerpDouble(_weightRest, _weightActive, t)!
    ..strokeCap = StrokeCap.round
    // Rounds every corner of the silhouette, which is what keeps the drawn set
    // in the same family as the rounded Material glyphs used elsewhere.
    ..strokeJoin = StrokeJoin.round
    ..color = alpha == 1 ? color : color.withValues(alpha: color.a * alpha);

  Paint _fill({double alpha = 1}) => Paint()
    ..style = PaintingStyle.fill
    ..color = alpha == 1 ? color : color.withValues(alpha: color.a * alpha);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _grid, size.height / _grid);

    switch (glyph) {
      case NavGlyph.home:
        _paintHome(canvas);
      case NavGlyph.explore:
        _paintExplore(canvas);
      case NavGlyph.create:
        _paintCreate(canvas);
      case NavGlyph.activity:
        _paintActivity(canvas);
      case NavGlyph.profile:
        _paintProfile(canvas);
    }

    canvas.restore();
  }

  void _paintHome(Canvas canvas) {
    // Roof and walls as one silhouette: the eaves do not overhang, so the mark
    // stays a single clean shape at 26px instead of growing a detail that turns
    // to mush.
    final body = Path()
      ..moveTo(3.4, 10.7)
      ..lineTo(10.7, 3.9)
      // The ridge is rounded rather than a point — a sharp apex is the first
      // thing to alias at this size.
      ..quadraticBezierTo(12, 2.75, 13.3, 3.9)
      ..lineTo(20.6, 10.7)
      ..lineTo(20.6, 17.2)
      ..quadraticBezierTo(20.6, 19.6, 18.2, 19.6)
      ..lineTo(5.8, 19.6)
      ..quadraticBezierTo(3.4, 19.6, 3.4, 17.2)
      ..close();

    // Open at the threshold, so unselected it strokes as a doorway rather than
    // a closed box.
    final door = Path()
      ..moveTo(9.4, 19.6)
      ..lineTo(9.4, 15.3)
      ..quadraticBezierTo(9.4, 12.7, 12, 12.7)
      ..quadraticBezierTo(14.6, 12.7, 14.6, 15.3)
      ..lineTo(14.6, 19.6);

    if (t > 0) {
      canvas.drawPath(
        // Subtracted, not painted over: the bar is translucent glass, so a hole
        // here shows the blurred feed through the doorway. Filling it with a
        // background colour would show a flat slab instead.
        Path.combine(PathOperation.difference, body, Path.from(door)..close()),
        _fill(alpha: t),
      );
    }

    canvas.drawPath(body, _stroke());
    // Once the body is solid the knockout draws the doorway on its own, so the
    // outline retires as the fill arrives.
    canvas.drawPath(door, _stroke(alpha: 1 - t));
  }

  void _paintExplore(Canvas canvas) {
    canvas.drawCircle(const Offset(12, 12), 8.7, _stroke());

    // A needle with a pinched waist rather than the flat parallelogram of the
    // stock compass: the concave edges are what make it read as swept.
    final needle = Path()
      ..moveTo(16.9, 7.1)
      ..quadraticBezierTo(14.2, 10.6, 13.4, 13.4)
      ..quadraticBezierTo(10.6, 14.2, 7.1, 16.9)
      ..quadraticBezierTo(9.8, 13.4, 10.6, 10.6)
      ..quadraticBezierTo(13.4, 9.8, 16.9, 7.1)
      ..close();

    if (t > 0) {
      // Only the east half takes ink, split down the needle's long axis. A
      // needle solid on both sides is just a slash; it is the lit half against
      // the unlit one that says compass.
      final lit = Path()
        ..moveTo(16.9, 7.1)
        ..quadraticBezierTo(14.2, 10.6, 13.4, 13.4)
        ..quadraticBezierTo(10.6, 14.2, 7.1, 16.9)
        ..close();
      canvas.drawPath(lit, _fill(alpha: t));
    }

    canvas.drawPath(needle, _stroke());
  }

  void _paintCreate(Canvas canvas) {
    // Heavier than the rest of the set: it sits on the brand disc, where the
    // surrounding fill eats a stroke that reads correctly against glass.
    final bar = _stroke(width: 2.4);
    canvas.drawLine(const Offset(7.9, 12), const Offset(16.1, 12), bar);
    canvas.drawLine(const Offset(12, 7.9), const Offset(12, 16.1), bar);
  }

  void _paintActivity(Canvas canvas) {
    // One beat, not a repeating trace: a dip, the spike, and the recovery, with
    // flat baseline either side so it reads as a reading rather than a zigzag.
    //
    // The amplitude is deliberately larger than the trace needs: sharing a row
    // with marks that fill their box, a shallow wave reads as a smaller icon
    // rather than a quieter one. The baseline tails are short for the same
    // reason — width spent on flat line is width the beat does not get.
    final pulse = Path()
      ..moveTo(3.3, 13.1)
      ..lineTo(7.0, 13.1)
      ..lineTo(9.0, 9.0)
      ..lineTo(11.4, 18.5)
      ..lineTo(13.9, 5.4)
      ..lineTo(16.1, 13.1)
      ..lineTo(20.7, 13.1);

    canvas.drawPath(pulse, _stroke());

    // The one mark with no interior to fill, so selection lands a bulb on the
    // peak instead — it grows out of the rounded join already there.
    if (t > 0) {
      canvas.drawCircle(const Offset(13.9, 5.4), 1.9 * t, _fill());
    }
  }

  void _paintProfile(Canvas canvas) {
    const head = Offset(12, 8.7);
    const headRadius = 3.85;

    final shoulders = Path()
      ..moveTo(4.6, 19.9)
      ..cubicTo(4.9, 16.0, 8.0, 13.9, 12.0, 13.9)
      ..cubicTo(16.0, 13.9, 19.1, 16.0, 19.4, 19.9);

    canvas.drawCircle(head, headRadius, _stroke());

    if (t > 0) {
      final closed = Path.from(shoulders)..close();
      canvas.drawCircle(head, headRadius, _fill(alpha: t));
      canvas.drawPath(closed, _fill(alpha: t));
      // Stroked closed, so the arc's two ends meet in a join along the baseline
      // instead of ending in round caps. Capped, they hang below the fill's
      // flat bottom as a pair of little feet.
      canvas.drawPath(closed, _stroke(alpha: t));
    }

    // The open arc is the unselected silhouette, and retires as the closed one
    // above takes over. Their outlines coincide everywhere but the baseline, so
    // the handover is invisible mid-morph.
    if (t < 1) canvas.drawPath(shoulders, _stroke(alpha: 1 - t));
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.t != t ||
      oldDelegate.color != color;
}

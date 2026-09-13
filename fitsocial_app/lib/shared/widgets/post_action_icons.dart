import 'package:flutter/widgets.dart';

/// The comment and share marks on a post's action row, drawn as paths rather
/// than pulled from the Material icon font.
///
/// Same reason the nav is hand-drawn in `nav_icons.dart`, and the same 24-unit
/// grid at the same weight, so the two sets read as one family: the stock
/// glyphs were each drawn for a different product and it shows when they sit
/// side by side. `mode_comment_outlined` is a squared-off box with a stub of a
/// tail; `send_outlined` is a filled-looking wedge. Neither matches the rounded
/// silhouettes the rest of the app is built from.
///
/// These two are the marks the feed was designed around: a round-shouldered
/// bubble that actually flicks a tail, and an open paper plane with its fold
/// drawn in rather than implied.
enum PostActionGlyph {
  /// A speech bubble, wider than it is tall, with a tail off the bottom-left.
  comment,

  /// An outlined paper plane. Deliberately not the platform's share glyph —
  /// this opens FitSocial's own options first, Pulse among them, and only
  /// reaches the OS sheet if that is what the user picks.
  send,
}

/// A [PostActionGlyph] rendered at [size] in [color].
///
/// Stateless where [NavIcon] animates: nothing about a post's action row
/// morphs. The heart beside these carries the row's only selected state, and it
/// draws itself.
class PostActionIcon extends StatelessWidget {
  const PostActionIcon({
    required this.glyph,
    required this.color,
    this.size = 22,
    super.key,
  });

  final PostActionGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      isComplex: false,
      painter: _PostGlyphPainter(glyph: glyph, color: color),
    );
  }
}

class _PostGlyphPainter extends CustomPainter {
  const _PostGlyphPainter({required this.glyph, required this.color});

  final PostActionGlyph glyph;
  final Color color;

  /// The design grid, shared with `nav_icons.dart`.
  static const double _grid = 24;

  /// The nav's resting weight. These glyphs sit a few pixels from that bar and
  /// have to be cut from the same stock.
  static const double _weight = 1.9;

  Paint get _stroke => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _weight
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _grid, size.height / _grid);

    switch (glyph) {
      case PostActionGlyph.comment:
        _paintComment(canvas);
      case PostActionGlyph.send:
        _paintSend(canvas);
    }

    canvas.restore();
  }

  void _paintComment(Canvas canvas) {
    // One closed silhouette: the bubble and its tail are the same outline, so
    // the join where the tail leaves the body is a corner of the shape rather
    // than a second path laid over the first. Overlapping strokes are what make
    // a small bubble look furry.
    final bubble = Path()
      ..moveTo(20.5, 12.2)
      // Right shoulder down to the base.
      ..cubicTo(20.5, 16.4, 16.7, 19.8, 12, 19.8)
      // The base runs almost flat to where the tail starts — a wide radius over
      // this little span, so it is drawn as the near-straight line it reads as.
      ..quadraticBezierTo(10.6, 19.76, 9.3, 19.4)
      // Out to the point of the tail and back up into the body.
      ..lineTo(4, 20.8)
      ..lineTo(5.5, 16.6)
      // Left shoulder. Cubic rather than an arc so the whole mark is one kind
      // of curve; the control points are the exact 37.7° arc the drawing had.
      ..cubicTo(4.53, 15.34, 4, 13.79, 4, 12.2)
      ..cubicTo(4, 8, 7.8, 4.6, 12.5, 4.6)
      ..cubicTo(17.2, 4.6, 20.5, 8, 20.5, 12.2)
      ..close();

    canvas.drawPath(bubble, _stroke);
  }

  void _paintSend(Canvas canvas) {
    // The plane's silhouette: nose, tail fin, the notch between the two wings,
    // and back along the leading edge.
    final body = Path()
      ..moveTo(21, 3)
      ..lineTo(14.2, 21)
      ..lineTo(10.5, 13.5)
      ..lineTo(3, 9.8)
      ..close();

    // The fold, drawn rather than left out. Without it the outline is a
    // quadrilateral that reads as an arrowhead; this one line is the whole
    // difference between a plane and a chevron.
    final fold = Path()
      ..moveTo(21, 3)
      ..lineTo(10.5, 13.5);

    canvas.drawPath(body, _stroke);
    canvas.drawPath(fold, _stroke);
  }

  @override
  bool shouldRepaint(_PostGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

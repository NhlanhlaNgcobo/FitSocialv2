import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The typefaces the Pulse text tool offers, in the order they appear.
///
/// Instagram's set, in spirit: one plain face and then a handful of loud,
/// distinct voices — the point of switching is that each one changes the
/// whole mood of the card, so near-duplicates earn nothing.
enum PulseFont {
  classic,
  modern,
  neon,
  typewriter,
  strong,
  elegant;

  /// Stored form. Explicit rather than `name` so a rename of the enum can never
  /// silently change what is already in Firestore.
  String get key {
    switch (this) {
      case PulseFont.classic:
        return 'classic';
      case PulseFont.modern:
        return 'modern';
      case PulseFont.neon:
        return 'neon';
      case PulseFont.typewriter:
        return 'typewriter';
      case PulseFont.strong:
        return 'strong';
      case PulseFont.elegant:
        return 'elegant';
    }
  }

  /// Falls back to [classic], so a document written by a newer build with a
  /// face this one does not ship still reads.
  static PulseFont fromKey(String? value) {
    for (final font in values) {
      if (font.key == value) return font;
    }
    return PulseFont.classic;
  }

  /// What the chip in the picker says.
  String get label {
    switch (this) {
      case PulseFont.classic:
        return 'Classic';
      case PulseFont.modern:
        return 'Modern';
      case PulseFont.neon:
        return 'Neon';
      case PulseFont.typewriter:
        return 'Typewriter';
      case PulseFont.strong:
        return 'Strong';
      case PulseFont.elegant:
        return 'Elegant';
    }
  }

  /// The face's own metrics, before colour and size are applied.
  ///
  /// Each face is tuned individually rather than sharing one weight: Anton is
  /// already as heavy as it gets, Pacifico has one weight, and Montserrat and
  /// Playfair are variable fonts that are told their weight through an axis.
  TextStyle get baseStyle {
    switch (this) {
      case PulseFont.classic:
        return const TextStyle(fontWeight: FontWeight.w800, height: 1.2);
      case PulseFont.modern:
        return const TextStyle(
          fontFamily: 'PulseModern',
          fontVariations: [FontVariation('wght', 600)],
          letterSpacing: 1.5,
          height: 1.25,
        );
      case PulseFont.neon:
        return const TextStyle(fontFamily: 'PulseNeon', height: 1.45);
      case PulseFont.typewriter:
        return const TextStyle(
          fontFamily: 'PulseTypewriter',
          fontWeight: FontWeight.w700,
          height: 1.3,
        );
      case PulseFont.strong:
        return const TextStyle(
          fontFamily: 'PulseStrong',
          letterSpacing: 1,
          height: 1.15,
        );
      case PulseFont.elegant:
        return const TextStyle(
          fontFamily: 'PulseElegant',
          fontStyle: FontStyle.italic,
          fontVariations: [FontVariation('wght', 700)],
          height: 1.25,
        );
    }
  }

  /// Anton and Playfair sit visually larger than the rest at the same point
  /// size, Pacifico smaller; this pulls each face to the same apparent height.
  double get sizeFactor {
    switch (this) {
      case PulseFont.strong:
        return 1.1;
      case PulseFont.neon:
        return 0.95;
      case PulseFont.elegant:
        return 1.05;
      case PulseFont.classic:
      case PulseFont.modern:
      case PulseFont.typewriter:
        return 1;
    }
  }
}

enum PulseTextAlignment {
  left,
  center,
  right;

  String get key => name;

  static PulseTextAlignment fromKey(String? value) {
    for (final alignment in values) {
      if (alignment.key == value) return alignment;
    }
    return PulseTextAlignment.center;
  }

  PulseTextAlignment get next {
    switch (this) {
      case PulseTextAlignment.center:
        return PulseTextAlignment.left;
      case PulseTextAlignment.left:
        return PulseTextAlignment.right;
      case PulseTextAlignment.right:
        return PulseTextAlignment.center;
    }
  }

  TextAlign get textAlign {
    switch (this) {
      case PulseTextAlignment.left:
        return TextAlign.left;
      case PulseTextAlignment.center:
        return TextAlign.center;
      case PulseTextAlignment.right:
        return TextAlign.right;
    }
  }

  IconData get icon {
    switch (this) {
      case PulseTextAlignment.left:
        return Icons.format_align_left_rounded;
      case PulseTextAlignment.center:
        return Icons.format_align_center_rounded;
      case PulseTextAlignment.right:
        return Icons.format_align_right_rounded;
    }
  }
}

/// What sits behind the letters. Instagram's "A" button cycles through these.
enum PulseTextBackdrop {
  /// Bare type, with a soft shadow so it holds up over a busy photo.
  none,

  /// A plate in the chosen colour, with the type flipped to whatever reads
  /// against it.
  solid,

  /// A smoked plate under type in the chosen colour.
  translucent;

  String get key => name;

  static PulseTextBackdrop fromKey(String? value) {
    for (final backdrop in values) {
      if (backdrop.key == value) return backdrop;
    }
    return PulseTextBackdrop.none;
  }

  PulseTextBackdrop get next {
    switch (this) {
      case PulseTextBackdrop.none:
        return PulseTextBackdrop.solid;
      case PulseTextBackdrop.solid:
        return PulseTextBackdrop.translucent;
      case PulseTextBackdrop.translucent:
        return PulseTextBackdrop.none;
    }
  }
}

/// The colours on offer under the text field.
///
/// White leads because it is what almost everything gets written in; the rest
/// are saturated enough to survive a solid plate and a photo alike.
abstract final class PulseTextColors {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const all = <Color>[
    white,
    black,
    Color(0xFFFF6B1A), // the app's own orange
    Color(0xFFFF3B30),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF32ADE6),
    Color(0xFF5856D6),
    Color(0xFFFF2D55),
    Color(0xFFFFB6C1),
    Color(0xFFB4E5A2),
    Color(0xFFC7B8FF),
  ];
}

/// How a written Pulse looks and where it sits: face, colour, alignment,
/// backdrop, size and placement, all in one value so the composer, the
/// rasteriser and the viewer draw the same thing from it.
///
/// Placement is normalised to the frame — [x] and [y] are the centre of the
/// text as fractions of the frame's width and height — so a card written on
/// one phone lands in the same place on another. [scale] multiplies the
/// length-derived base size; [rotation] is radians, clockwise.
@immutable
class PulseTextStyle {
  const PulseTextStyle({
    this.font = PulseFont.classic,
    this.color = PulseTextColors.white,
    this.alignment = PulseTextAlignment.center,
    this.backdrop = PulseTextBackdrop.none,
    this.scale = 1,
    this.x = 0.5,
    this.y = 0.5,
    this.rotation = 0,
  });

  static const defaults = PulseTextStyle();

  static const double minScale = 0.5;
  static const double maxScale = 2.6;

  final PulseFont font;
  final Color color;
  final PulseTextAlignment alignment;
  final PulseTextBackdrop backdrop;
  final double scale;
  final double x;
  final double y;
  final double rotation;

  /// What the letters themselves are painted in. On a solid plate the plate
  /// takes the colour and the type flips to contrast with it.
  Color get foreground {
    if (backdrop != PulseTextBackdrop.solid) return color;
    return _isLight(color) ? PulseTextColors.black : PulseTextColors.white;
  }

  /// The plate, or null for bare type.
  Color? get plate {
    switch (backdrop) {
      case PulseTextBackdrop.none:
        return null;
      case PulseTextBackdrop.solid:
        return color;
      case PulseTextBackdrop.translucent:
        // Smoke for light type, milk for dark: the plate exists to give the
        // letters something to stand out from.
        return _isLight(color)
            ? const Color(0x59000000)
            : const Color(0x8CFFFFFF);
    }
  }

  static bool _isLight(Color color) => color.computeLuminance() > 0.5;

  /// The full style for the letters, from a [baseSize] that this style's own
  /// [scale] and the face's sizing correction are then applied to.
  ///
  /// Complete in itself (`inherit: false`), so neither a [Text] nor a
  /// [TextField] merges the app theme's own letter spacing into it. The width
  /// of a line is measured from this style before it is laid out, and the two
  /// only agree if nothing is added between.
  TextStyle resolve(double baseSize) {
    final size = baseSize * scale * font.sizeFactor;
    final base = font.baseStyle;
    return base.copyWith(
      inherit: false,
      color: foreground,
      fontSize: size,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: base.letterSpacing ?? 0,
      wordSpacing: 0,
      decoration: TextDecoration.none,
      shadows: _shadows(size),
    );
  }

  List<Shadow> _shadows(double size) {
    if (font == PulseFont.neon) {
      // The glow is the whole point of the face. It is the type's own colour
      // spread wide, so white neon reads white-hot and pink reads pink.
      final glow = foreground;
      return [
        Shadow(color: glow.withValues(alpha: 0.9), blurRadius: size * 0.25),
        Shadow(color: glow.withValues(alpha: 0.6), blurRadius: size * 0.6),
      ];
    }
    if (backdrop != PulseTextBackdrop.none) return const [];
    // Bare type over a photo needs an edge. Kept soft and short: a hard
    // outline would read as a meme, and this is a story.
    return [
      Shadow(
        color: const Color(0x66000000),
        blurRadius: math.max(4, size * 0.12),
        offset: const Offset(0, 1),
      ),
    ];
  }

  PulseTextStyle copyWith({
    PulseFont? font,
    Color? color,
    PulseTextAlignment? alignment,
    PulseTextBackdrop? backdrop,
    double? scale,
    double? x,
    double? y,
    double? rotation,
  }) {
    return PulseTextStyle(
      font: font ?? this.font,
      color: color ?? this.color,
      alignment: alignment ?? this.alignment,
      backdrop: backdrop ?? this.backdrop,
      scale: scale ?? this.scale,
      x: x ?? this.x,
      y: y ?? this.y,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toMap() => {
        'font': font.key,
        'color': color.toARGB32(),
        'align': alignment.key,
        'backdrop': backdrop.key,
        'scale': scale,
        'x': x,
        'y': y,
        'rotation': rotation,
      };

  /// Null for anything that is not a map — a Pulse written before the text
  /// tool existed has no style, and the viewer draws it the old way.
  static PulseTextStyle? fromMap(Object? value) {
    if (value is! Map) return null;
    return PulseTextStyle(
      font: PulseFont.fromKey(value['font']?.toString()),
      color: _readColor(value['color']),
      alignment: PulseTextAlignment.fromKey(value['align']?.toString()),
      backdrop: PulseTextBackdrop.fromKey(value['backdrop']?.toString()),
      scale: _readDouble(value['scale'], 1).clamp(minScale, maxScale),
      x: _readDouble(value['x'], 0.5).clamp(0.0, 1.0),
      y: _readDouble(value['y'], 0.5).clamp(0.0, 1.0),
      rotation: _readDouble(value['rotation'], 0),
    );
  }

  static Color _readColor(Object? value) {
    if (value is int) return Color(value);
    return PulseTextColors.white;
  }

  static double _readDouble(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is PulseTextStyle &&
      other.font == font &&
      other.color == color &&
      other.alignment == alignment &&
      other.backdrop == backdrop &&
      other.scale == scale &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation;

  @override
  int get hashCode =>
      Object.hash(font, color, alignment, backdrop, scale, x, y, rotation);
}

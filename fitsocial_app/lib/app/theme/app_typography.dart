import 'package:flutter/material.dart';

/// Named text styles for the handful of places the app already leans on
/// deliberate tracking and leading, gathered so the numbers live in one place
/// instead of being re-typed at every call site.
///
/// Every size here is lifted from where it was already on screen — the run,
/// workout and meal cards' stat numerals, the app bar's title — rather than
/// invented, so applying a token changes nothing about how the app looks
/// today. What it buys is one definition to tune later instead of three or
/// four that have to be kept in step by hand.
///
/// Colour is deliberately not part of any of these: every call site already
/// resolves its own — a card's on-media white, a palette's adaptive text —
/// and `.copyWith(color: ...)` layers it on the same way the rest of the app
/// layers colour onto Material's own text styles.
abstract final class AppTypography {
  /// The big number on a run, workout or meal card — distance, pace, calorie
  /// total. Tight enough that a two-digit and a four-digit reading sit at the
  /// same visual weight instead of the wider one looking looser.
  static const TextStyle statNumeralLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -0.8,
  );

  /// The same numeral, sized for a strip of several side by side — a
  /// workout's per-exercise stat cells — where [statNumeralLarge] would
  /// crowd its neighbours. Carries tabular figures so a column of them lines
  /// up instead of drifting with every digit's own width.
  static const TextStyle statNumeralCompact = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A numeral small enough to sit inline in a caption or a branding chip,
  /// rather than stand on its own the way the two above do.
  static const TextStyle statNumeralInline = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1,
    letterSpacing: -0.3,
  );

  /// A screen's own title, in its app bar.
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
}

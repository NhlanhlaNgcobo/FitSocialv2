import 'package:flutter/material.dart';

/// Every colour in the app that changes with the theme.
///
/// Lives on [ThemeData.extensions] rather than in a bag of `static const`s, so
/// a widget reading `context.palette.text` re-reads it when the theme flips.
/// That dependency is the whole reason for this class: statics can't rebuild.
///
/// What is *not* here is as deliberate as what is. The brand orange, and the
/// literal white/black used on top of photos and on the orange discs, stay in
/// `AppColors` as compile-time constants — they mean the same thing in both
/// themes, and keeping them const keeps their call sites const too.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.stroke,
    required this.text,
    required this.muted,
    required this.success,
    required this.danger,
    required this.brandText,
    required this.overlay,
    required this.glassTop,
    required this.glassBottom,
    required this.glassSheen,
    required this.glassRimHigh,
    required this.glassRimSoft,
    required this.navShadow,
  });

  /// Which end of the scale this palette sits at. Drives the few decisions that
  /// aren't a colour — status-bar icon brightness, the Google Maps style JSON.
  final bool isDark;

  /// The page behind everything.
  final Color background;

  /// Cards, sheets, dialogs — one step off the page.
  final Color surface;

  /// Raised or inset fills sitting on top of [surface]: chips, segment pills,
  /// input wells.
  final Color surfaceHigh;

  /// Hairline borders and dividers.
  final Color stroke;

  /// Primary foreground. The adaptive counterpart to `AppColors.onBrand` —
  /// near white on dark, near black on cream.
  final Color text;

  /// Secondary foreground: subtitles, timestamps, inactive glyphs.
  final Color muted;

  final Color success;
  final Color danger;

  /// The brand orange at a weight that stays legible as *small text*.
  ///
  /// `AppColors.orangeBright` is tuned for fills, icons and large numerals; at
  /// 12–14px on cream it goes muddy, so accent labels use this instead.
  final Color brandText;

  /// The base for translucent fills — `overlay.withValues(alpha: 0.06)` and
  /// friends. White on dark, black on light, so a fill that lifts a surface in
  /// one theme still lifts it in the other instead of inverting into a smear.
  final Color overlay;

  /// Top and bottom of the bottom nav's glass body.
  final Color glassTop;
  final Color glassBottom;

  /// The band of light along the top edge of the glass. Stays a *white*
  /// highlight in both themes — glass catches light the same way on cream as it
  /// does on black — which is why it isn't derived from [overlay].
  final Color glassSheen;

  /// The lit rim around the glass capsule, brightest at the top ([glassRimHigh])
  /// and fading through [glassRimSoft] to nothing at the bottom.
  final Color glassRimHigh;
  final Color glassRimSoft;

  /// Drop shadow under the floating nav. Far softer on cream, where a heavy
  /// shadow reads as dirt rather than elevation.
  final Color navShadow;

  /// The app as it has always looked. These are the exact values the app
  /// shipped with — dark mode must not drift.
  static const AppPalette dark = AppPalette(
    isDark: true,
    background: Color(0xFF050505),
    surface: Color(0xFF111111),
    surfaceHigh: Color(0xFF1A1A1A),
    stroke: Color(0xFF2B2B2B),
    text: Color(0xFFF7F7F7),
    muted: Color(0xFFAAAAAA),
    success: Color(0xFF31C46C),
    danger: Color(0xFFE85D5D),
    brandText: Color(0xFFFF6B1A),
    overlay: Color(0xFFFFFFFF),
    glassTop: Color(0x9E1A1A1A),
    glassBottom: Color(0xB8050505),
    glassSheen: Color(0x1AFFFFFF),
    glassRimHigh: Color(0x73FFFFFF),
    glassRimSoft: Color(0x1AFFFFFF),
    navShadow: Color(0x8C000000),
  );

  /// The warm cream of the FitSocial landing page: paper-coloured page, white
  /// cards, near-black text, the same orange.
  ///
  /// Deliberately not pure white. The brand's orange sits on cream everywhere
  /// else it appears, and a #FFFFFF page under it reads as a different product.
  static const AppPalette light = AppPalette(
    isDark: false,
    background: Color(0xFFF5F1EA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEFE9DF),
    stroke: Color(0xFFE4DED2),
    text: Color(0xFF14100C),
    muted: Color(0xFF6F6A62),
    success: Color(0xFF1E9E52),
    danger: Color(0xFFC0392B),
    brandText: Color(0xFFC2521A),
    overlay: Color(0xFF000000),
    glassTop: Color(0xB8FFFFFF),
    glassBottom: Color(0xC7EDE7DD),
    glassSheen: Color(0x73FFFFFF),
    glassRimHigh: Color(0x24000000),
    glassRimSoft: Color(0x0D000000),
    navShadow: Color(0x1F000000),
  );

  @override
  AppPalette copyWith({
    bool? isDark,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? stroke,
    Color? text,
    Color? muted,
    Color? success,
    Color? danger,
    Color? brandText,
    Color? overlay,
    Color? glassTop,
    Color? glassBottom,
    Color? glassSheen,
    Color? glassRimHigh,
    Color? glassRimSoft,
    Color? navShadow,
  }) {
    return AppPalette(
      isDark: isDark ?? this.isDark,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      stroke: stroke ?? this.stroke,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      brandText: brandText ?? this.brandText,
      overlay: overlay ?? this.overlay,
      glassTop: glassTop ?? this.glassTop,
      glassBottom: glassBottom ?? this.glassBottom,
      glassSheen: glassSheen ?? this.glassSheen,
      glassRimHigh: glassRimHigh ?? this.glassRimHigh,
      glassRimSoft: glassRimSoft ?? this.glassRimSoft,
      navShadow: navShadow ?? this.navShadow,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;

    return AppPalette(
      // Not a colour, so it can't be blended — it flips at the midpoint, which
      // is also where the crossfade stops reading as the old theme.
      isDark: t < 0.5 ? isDark : other.isDark,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      glassTop: Color.lerp(glassTop, other.glassTop, t)!,
      glassBottom: Color.lerp(glassBottom, other.glassBottom, t)!,
      glassSheen: Color.lerp(glassSheen, other.glassSheen, t)!,
      glassRimHigh: Color.lerp(glassRimHigh, other.glassRimHigh, t)!,
      glassRimSoft: Color.lerp(glassRimSoft, other.glassRimSoft, t)!,
      navShadow: Color.lerp(navShadow, other.navShadow, t)!,
    );
  }
}

/// `context.palette.text` — the way every widget reads a theme-dependent colour.
extension AppPaletteX on BuildContext {
  /// Falls back to [AppPalette.dark] rather than throwing, so a widget built
  /// outside the app's own theme (a bare `MaterialApp` in a test, a raw
  /// `Overlay`) still renders instead of crashing.
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

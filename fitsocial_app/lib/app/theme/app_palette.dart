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
    required this.brand,
    required this.brandText,
    required this.brandSoft,
    required this.brandSoftStroke,
    required this.overlay,
    required this.glassTop,
    required this.glassBottom,
    required this.glassSheen,
    required this.glassRimHigh,
    required this.glassRimSoft,
    required this.glassFloor,
    required this.liquidTint,
    required this.paneShadow,
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

  /// The brand orange at the weight that suits a *fill on an app surface* —
  /// a progress bar, a chart column, an active glyph, the Create disc.
  ///
  /// On dark this is the lit orange the app was built around. On light it is
  /// pulled down: `AppColors.orangeBright` against white has nothing darker
  /// beside it, so it stops reading as an accent and starts reading as a
  /// highlighter. The deeper orange carries the same weight on paper that the
  /// lit one carries on black.
  ///
  /// Fills that sit on a *photo* or on the orange itself keep using
  /// `AppColors`: their backdrop is the same in both themes.
  final Color brand;

  /// The brand orange at a weight that stays legible as *small text*.
  ///
  /// [brand] is tuned for fills, icons and large numerals; at 12–14px on cream
  /// it goes muddy, so accent labels use this instead.
  final Color brandText;

  /// The tinted fill behind a selected chip, an active row, an icon well.
  ///
  /// A solid colour rather than the orange at low alpha. Alpha was the old way
  /// and it only ever worked on dark: 16% orange over near-black settles into a
  /// warm ember, while the same 16% over white turns into pale peach.
  final Color brandSoft;

  /// The border around [brandSoft].
  final Color brandSoftStroke;

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

  /// The dark half of what a pane of liquid glass reflects.
  ///
  /// [glassRimHigh] is the sky in that little environment; this is the
  /// floor. The bevel picks up one along its upper edge and the other along
  /// its lower, and the difference between them is the whole read of
  /// thickness -- a rim lit evenly all the way round looks like a sticker.
  ///
  /// Near-black on dark, where the floor really is the page. On light it is
  /// a warm mid grey rather than the page's own cream: the pane needs
  /// somewhere darker than itself to sit against, and cream on cream is the
  /// flat-sheet failure this palette was tuned against.
  final Color glassFloor;

  /// What liquid glass mixes into the backdrop it is bending, with the alpha
  /// carrying *how much*.
  ///
  /// Deliberately faint. The frosted pane above holds text legible by fogging
  /// what is behind it; a lens holds it with refraction and a lit rim instead,
  /// and past roughly 20% this stops being glass and becomes the fog again.
  final Color liquidTint;

  /// What a pane of glass drops onto the page beneath it.
  ///
  /// Only the light theme has one, and the reason is not taste. On near-black a
  /// pane separates from the page by being *brighter* at its rim; on cream
  /// there is no brighter to go, so the only way it reads as sitting above the
  /// page is by darkening what is under it. Fully transparent on dark, where
  /// the lit rim already does this job and a shadow would just be fill rate.
  final Color paneShadow;

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
    brand: Color(0xFFFF6B1A),
    brandText: Color(0xFFFF6B1A),
    // The old `orangeBright @ 18%` over `surface`, resolved to the solid it
    // always painted. Dark must not drift.
    brandSoft: Color(0xFF3C2113),
    brandSoftStroke: Color(0xFF703515),
    overlay: Color(0xFFFFFFFF),
    glassTop: Color(0x9E1A1A1A),
    glassBottom: Color(0xB8050505),
    glassSheen: Color(0x1AFFFFFF),
    glassRimHigh: Color(0x73FFFFFF),
    glassRimSoft: Color(0x1AFFFFFF),
    glassFloor: Color(0xFF000000),
    liquidTint: Color(0x1F000000),
    paneShadow: Color(0x00000000),
    navShadow: Color(0x8C000000),
  );

  /// Warm paper: a soft page, white cards, near-black text, the same orange
  /// carried at a weight that suits daylight.
  ///
  /// Deliberately not pure white. The brand's orange sits on a warm ground
  /// everywhere else it appears, and a #FFFFFF page under it reads as a
  /// different product.
  ///
  /// Two things this palette is tuned against, both of which made the first
  /// light theme read as washed-out:
  ///
  /// The ramp needs *steps*. Page, card, well and hairline all sat within a few
  /// points of each other, so nothing had an edge and every screen turned to
  /// one flat sheet of cream. Each rung here is far enough from its neighbour
  /// to be seen without any of them turning grey.
  ///
  /// And the page needs less yellow. The old cream ran eleven points from red
  /// to blue, which is enough of a cast to look like ageing paper rather than a
  /// chosen colour. This one keeps the warmth at roughly half that spread.
  static const AppPalette light = AppPalette(
    isDark: false,
    background: Color(0xFFF3F1EC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEAE6DE),
    stroke: Color(0xFFDCD7CD),
    text: Color(0xFF17130F),
    muted: Color(0xFF6B665E),
    // Both pulled down from the dark theme's values. A hue that reads as
    // "confident" against near-black reads as "neon" against white, because on
    // white it is the darkest thing in view and the eye has nothing to measure
    // it against.
    success: Color(0xFF1B8A4B),
    danger: Color(0xFFB3382A),
    brand: Color(0xFFDC5A11),
    brandText: Color(0xFFB44A12),
    brandSoft: Color(0xFFF7E7DA),
    brandSoftStroke: Color(0xFFE8C6AC),
    overlay: Color(0xFF000000),
    glassTop: Color(0xC7FFFFFF),
    glassBottom: Color(0xD1EFECE5),
    glassSheen: Color(0x8CFFFFFF),
    glassRimHigh: Color(0x1F000000),
    glassRimSoft: Color(0x0A000000),
    glassFloor: Color(0xFF8A8378),
    // 78% white, the same weight the frosted pane used before the lens
    // arrived. The 14% it briefly ran at is invisible on cream: the card
    // loses its surface entirely and only the hairline is left, which is
    // the exact flat-sheet-of-cream failure this palette was tuned against.
    liquidTint: Color(0xC7FFFFFF),
    paneShadow: Color(0x1F000000),
    navShadow: Color(0x1A000000),
  );

  /// An identifying hue, adjusted for the surface it is about to be drawn on.
  ///
  /// The app's non-brand accents — the four Create actions, the progress
  /// metrics, the macro bars, the reactions — were each picked against a
  /// near-black page, where a lit hue reads as confident. The same hue on white
  /// turns to candy: nothing around it is darker, so it stops identifying a
  /// thing and starts looking like a highlighter.
  ///
  /// So on light every hue is deepened toward the palette's own warm ink, which
  /// both restores the weight it had on black and keeps the whole set sitting
  /// in one family instead of drifting apart into unrelated pastels. Dark hands
  /// the hue back untouched.
  ///
  /// Pass the hue the design names — `_kRunAccent`, `AppColors.orangeBright` —
  /// and let this decide what to paint. Colours that sit on a *photo* skip it:
  /// media looks the same in both themes.
  Color accent(Color hue) =>
      isDark ? hue : Color.lerp(hue, const Color(0xFF1A120B), 0.34)!;

  /// The tinted fill that sits behind [accent] — an icon well, a selected chip.
  ///
  /// Built from the *adjusted* hue rather than the raw one, which is what keeps
  /// a light-mode well quiet: tinting with the lit hue is how the Create page
  /// ended up with a row of pastel sweets.
  Color accentFill(Color hue) => Color.alphaBlend(
        accent(hue).withValues(alpha: isDark ? 0.18 : 0.10),
        surface,
      );

  /// The border around [accentFill].
  Color accentStroke(Color hue) => Color.alphaBlend(
        accent(hue).withValues(alpha: isDark ? 0.38 : 0.24),
        surface,
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
    Color? brand,
    Color? brandText,
    Color? brandSoft,
    Color? brandSoftStroke,
    Color? overlay,
    Color? glassTop,
    Color? glassBottom,
    Color? glassSheen,
    Color? glassRimHigh,
    Color? glassRimSoft,
    Color? glassFloor,
    Color? liquidTint,
    Color? paneShadow,
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
      brand: brand ?? this.brand,
      brandText: brandText ?? this.brandText,
      brandSoft: brandSoft ?? this.brandSoft,
      brandSoftStroke: brandSoftStroke ?? this.brandSoftStroke,
      overlay: overlay ?? this.overlay,
      glassTop: glassTop ?? this.glassTop,
      glassBottom: glassBottom ?? this.glassBottom,
      glassSheen: glassSheen ?? this.glassSheen,
      glassRimHigh: glassRimHigh ?? this.glassRimHigh,
      glassRimSoft: glassRimSoft ?? this.glassRimSoft,
      glassFloor: glassFloor ?? this.glassFloor,
      liquidTint: liquidTint ?? this.liquidTint,
      paneShadow: paneShadow ?? this.paneShadow,
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
      brand: Color.lerp(brand, other.brand, t)!,
      brandText: Color.lerp(brandText, other.brandText, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandSoftStroke: Color.lerp(brandSoftStroke, other.brandSoftStroke, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      glassTop: Color.lerp(glassTop, other.glassTop, t)!,
      glassBottom: Color.lerp(glassBottom, other.glassBottom, t)!,
      glassSheen: Color.lerp(glassSheen, other.glassSheen, t)!,
      glassRimHigh: Color.lerp(glassRimHigh, other.glassRimHigh, t)!,
      glassRimSoft: Color.lerp(glassRimSoft, other.glassRimSoft, t)!,
      glassFloor: Color.lerp(glassFloor, other.glassFloor, t)!,
      liquidTint: Color.lerp(liquidTint, other.liquidTint, t)!,
      paneShadow: Color.lerp(paneShadow, other.paneShadow, t)!,
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

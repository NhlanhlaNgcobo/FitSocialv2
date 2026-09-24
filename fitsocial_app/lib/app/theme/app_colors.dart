import 'package:flutter/material.dart';

/// Colours that mean the same thing in light mode and dark mode.
///
/// Everything that *changes* with the theme lives on `AppPalette` and is read
/// through `context.palette`. Only fixed values are left here, which is what
/// lets their call sites stay `const`.
///
/// The rule for telling them apart: ask what the colour sits on. If it sits on
/// the page or a card, it is theme-dependent and belongs in the palette. If it
/// sits on the orange or on a user's photo, that backdrop is the same in both
/// themes and so is the colour on top of it.
abstract final class AppColors {
  /// Brand orange, deep. Used where the orange carries small text or needs to
  /// hold its own against white.
  static const Color orange = Color(0xFFD35400);

  /// Brand orange, lit. The default: fills, glyphs, the Create disc, progress.
  static const Color orangeBright = Color(0xFFFF6B1A);

  /// Foreground on a brand-orange fill — the `+` in the Create disc, the label
  /// on a primary button. Orange is orange in both themes, so this is fixed.
  static const Color onBrand = Color(0xFFF7F7F7);

  /// The dark foreground for the places that fill *solid* orange and need
  /// contrast the other way — a selected filter pill, a logged day in the
  /// activity grid. Also fixed: the orange underneath it never changes.
  static const Color onBrandInk = Color(0xFF050505);

  /// Foreground over a user's photo or video: metric labels on a feed image,
  /// Pulse controls. Media is media in both themes.
  static const Color onMedia = Color(0xFFF7F7F7);

  /// The quiet register of [onMedia] — a disabled Pulse button, a caption hint.
  static const Color onMediaMuted = Color(0xFFAAAAAA);

  /// The letterbox behind a photo or video — Pulse's viewer and composer, the
  /// crop canvas. Immersive media surfaces stay dark in light mode, the same
  /// way Stories do, because a cream surround misreports what the media looks
  /// like.
  static const Color mediaBackdrop = Color(0xFF050505);

  /// Rule-of-thirds lines in the photo cropper. Drawn over the photo itself,
  /// so a faint light line: a solid dark one scored the picture into nine
  /// panes.
  static const Color cropGrid = Color(0x59F7F7F7);

  /// What the cropper lays over the part of the photo being cut away.
  static const Color cropDimmed = Color(0xCC050505);
}

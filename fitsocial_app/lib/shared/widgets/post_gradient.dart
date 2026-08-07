import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_palette.dart';

/// The gradient a post with no photo is drawn on, resolved for the theme in
/// force.
///
/// Stored gradients are *dark* pairs: a post's theme key resolves to one of
/// three charcoal/brown ramps built for the dark app, and those colours are
/// baked into the post when it is mapped, long before anything knows which
/// theme will draw it. Painted as-is on the light theme, a grid of photo-less
/// posts becomes a wall of dark blobs on cream.
///
/// So on light each colour is washed most of the way toward the card surface.
/// That keeps the post's own hue — burn stays warm, graphite stays neutral —
/// while letting the tile sit on the page instead of punching a hole in it.
/// Dark keeps the stored pair untouched.
List<Color> postGradientColors(List<Color> stored, AppPalette palette) {
  // Nothing stored: the fallback is already built from the palette and needs
  // no correction in either theme.
  if (stored.isEmpty) return [palette.surfaceHigh, palette.surface];
  if (palette.isDark) return stored;
  return [
    for (final color in stored) Color.lerp(color, palette.surface, 0.88)!,
  ];
}

/// Colour for text drawn on [postGradientColors].
///
/// Follows the tile rather than staying the on-media white, because unlike a
/// photo this backdrop flips with the theme.
Color postGradientTextColor(AppPalette palette) =>
    palette.isDark ? AppColors.onMedia : palette.text;

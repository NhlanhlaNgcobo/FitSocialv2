import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'liquid_glass.dart';

/// The well a form control sits in, as a pane of glass.
///
/// [DarkCard]'s sibling, one step down the scale. A card is a block on the
/// page and carries a margin, a shadow and [AppRadius.card]; a well is the
/// surface *under a field* and carries none of those, at [AppRadius.field], so
/// it lines up with the text inputs the theme draws.
///
/// ## Why it overrides the input theme
///
/// The app's `inputDecorationTheme` fills every field with an opaque
/// `palette.surface`. On its own that is right — a bare field needs a surface.
/// Inside a pane of glass it is a disaster: `InputBorder.none` removes a
/// field's outline but *not* its fill, so the field goes on painting an opaque
/// slab in the middle of the well and you get a box inside a box — and the
/// inner box is the one opaque thing on a page whose whole material is
/// supposed to be transparent.
///
/// So the well switches the fill off for everything under it. A field placed
/// in a well is automatically flat and transparent, and no call site has to
/// remember to ask.
class GlassWell extends StatelessWidget {
  const GlassWell({
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = AppRadius.field,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Defaults to the field radius. A well holding something bigger than a
  /// control — a whole block of them, say — can take [AppRadius.card] instead.
  final double radius;

  /// The hairline. Null takes `palette.stroke`; a field that is refusing what
  /// it has been given passes `palette.danger`, and the change is animated
  /// rather than cut.
  final Color? borderColor;

  /// How the hairline moves when it changes. Nothing animates while the colour
  /// stays put, so a well that never goes invalid pays nothing for this.
  static const Duration _borderFade = Duration(milliseconds: 200);

  /// What a field looks like once the well is supplying its surface: no fill,
  /// no outline of its own, and vertical padding only — the well already owns
  /// the horizontal inset.
  ///
  /// An [InputDecorationTheme] widget rather than a [Theme], and deliberately
  /// so. [LiquidGlass] already scopes one of these to drop the opaque fill, and
  /// `InputDecorationTheme.of` resolves to the nearest widget of that type
  /// before it ever consults `Theme.of`. A `Theme` here would sit *inside* the
  /// pane's own scope and be looked straight past; this one is nearer to the
  /// field, so it wins.
  static InputDecorationThemeData _fieldTheme(BuildContext context) =>
      InputDecorationTheme.of(context).copyWith(
        filled: false,
        fillColor: Colors.transparent,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      );

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    return LiquidGlass(
      borderRadius: shape,
      child: AnimatedContainer(
        duration: _borderFade,
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          // The hairline only. No fill: the lens supplies the surface, and the
          // border is the structural edge between one well and the next.
          borderRadius: shape,
          border: Border.all(color: borderColor ?? context.palette.stroke),
        ),
        child: InputDecorationTheme(
          data: _fieldTheme(context),
          child: child,
        ),
      ),
    );
  }
}

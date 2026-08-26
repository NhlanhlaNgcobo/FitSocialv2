import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../../app/theme/app_spacing.dart';
import 'glass.dart';
import 'liquid_glass.dart';

/// The app's card, and a pane of liquid glass.
///
/// There is no opaque variant any more. Every card is transparent and bends the
/// [LiquidBackdrop] the shell paints underneath — which is the whole reason
/// that backdrop exists, since a lens over a flat colour has nothing to
/// displace.
///
/// The card keeps its hairline border from the theme as the structural edge
/// between one card and the next; everything else about the finish — the bend,
/// the tint, the lit rim, the specular — belongs to [LiquidGlass].
class DarkCard extends StatelessWidget {
  const DarkCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin,
    this.onTap,
    this.semanticLabel,
    this.backdrop,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Space *outside* the pane. Null takes the Card default, which is 4 on every
  /// side — right for a card in a list, and 8 of unwanted height for a card
  /// that is one band in a column someone else is measuring.
  final EdgeInsetsGeometry? margin;

  /// Makes the whole card a target. Null leaves it inert, which is what most
  /// cards want.
  final VoidCallback? onTap;

  /// What tapping this card is for, read out when the visible content is a set
  /// of numbers rather than a sentence.
  final String? semanticLabel;

  /// Colour of the card's own, painted *below* the glass so the pane bends it
  /// along with everything else behind the card. A [GlassBloom] of whatever the
  /// card is about.
  ///
  /// Most cards want nothing here — the shell's backdrop is already something
  /// to look through, and a bloom on every card in a list is noise that
  /// scrolls.
  final Widget? backdrop;

  /// Matches the radius on the card shape in the theme, so the clip, the ripple
  /// and the shader's distance field all agree on where the card ends.
  static const double radius = AppRadius.card;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    Widget content = Padding(padding: padding, child: child);

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: content,
        ),
      );
    }

    return Card(
      margin: margin,
      // The lens supplies the surface now. An opaque fill here would be the one
      // thing standing between the glass and anything worth bending.
      color: Colors.transparent,
      // The lens is told not to clip itself here, so casting the shadow falls
      // to the card. Elevation rather than a DecoratedBox around the outside,
      // because the Card carries a margin and a shadow drawn around *that*
      // would sit detached from the shape casting it.
      //
      // Only the light theme has a shadow to cast; see [AppPalette.paneShadow].
      elevation: palette.paneShadow.a == 0 ? 0 : 6,
      shadowColor: palette.paneShadow,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Painted before the glass, so the BackdropFilter above samples it
          // and the card's own colour arrives already bent.
          if (backdrop case final backdrop?) Positioned.fill(child: backdrop),
          LiquidGlass(
            borderRadius: BorderRadius.circular(radius),
            // The Card already clips to this shape; a second rounded clip is a
            // saveLayer for nothing.
            clip: false,
            // A card with a backdrop of its own is using that colour to mean
            // something — the streak card's heat is the case this exists for —
            // so the fill steps back and lets more of it through.
            tintScale: backdrop == null ? 1 : 0.7,
            // Last, and unpositioned, so the Stack takes its size from the
            // content and the backdrop fills to match.
            child: content,
          ),
        ],
      ),
    );
  }
}

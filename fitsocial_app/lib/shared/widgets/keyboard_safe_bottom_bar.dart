import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How much space a bar pinned to the bottom of the screen has to leave under
/// itself to stay visible.
///
/// The keyboard when it is up, the system navigation bar when it is down —
/// whichever is taller, because the two are never both in play and neither is
/// reported by the other's field. `viewInsets` is zero with the keyboard down;
/// `padding` is zero with it up (the keyboard already covers the nav bar), so
/// taking the max of `viewInsets` and `viewPadding` is the one expression that
/// is right in both states.
double keyboardSafeBottomInset(MediaQueryData media) {
  return math.max(media.viewInsets.bottom, media.viewPadding.bottom);
}

/// Wraps a bar so the keyboard can never sit on top of it.
///
/// This exists because [Scaffold] does not do it. `_ScaffoldLayout` positions
/// `bottomNavigationBar` against the bottom of the Scaffold itself and only
/// hands `minInsets` to the body — so a text field placed in that slot is
/// covered by the very keyboard it raised. That was the bug on the post detail
/// page: you could type a comment but not see what you were typing.
///
/// Use instead of [SafeArea], not alongside it — the inset already accounts
/// for the gesture bar, and a SafeArea inside this would pad for it twice.
class KeyboardSafeBottomBar extends StatelessWidget {
  const KeyboardSafeBottomBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: keyboardSafeBottomInset(MediaQuery.of(context)),
      ),
      child: child,
    );
  }
}

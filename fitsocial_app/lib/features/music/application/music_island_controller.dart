import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long the expanded island waits before folding itself away.
const Duration kIslandIdleTimeout = Duration(seconds: 6);

/// Whether the island is showing its controls, and when it should stop.
///
/// A plain [ValueNotifier] rather than a Riverpod provider, and owned by the
/// widget in the app bar. That is deliberate: there is one island per screen,
/// its panel is an [OverlayEntry] anchored to that bar, and navigating away
/// must take the panel with it. Global state would outlive the bar it belongs
/// to and leave a card hanging over the next screen.
///
/// Kept out of the widget so the rule can be tested directly — it is a small
/// state machine over a timer, and exercising it through a widget tree would
/// only obscure what it does.
///
/// Expansion is never persisted across a collapse: the island always returns
/// to the pill, because the expanded form covers content and nobody asked for
/// it to stay.
class MusicIslandController extends ValueNotifier<bool> {
  MusicIslandController() : super(false);

  Timer? _idle;

  bool get isExpanded => value;

  /// Opens the controls and starts the clock.
  void expand() {
    value = true;
    _restartIdleTimer();
  }

  /// Called on any interaction with the island itself — a skip, a play, a tap.
  ///
  /// Pushes the collapse back rather than letting it fire mid-use: someone
  /// tapping skip three times is still using it on the third tap.
  void keepAlive() {
    if (!value) return;
    _restartIdleTimer();
  }

  /// Folds it back to the pill. Safe to call when already collapsed, which is
  /// what lets every outside tap route straight into it.
  void collapse() {
    _idle?.cancel();
    _idle = null;
    if (value) value = false;
  }

  void toggle() => value ? collapse() : expand();

  void _restartIdleTimer() {
    _idle?.cancel();
    _idle = Timer(kIslandIdleTimeout, collapse);
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }
}

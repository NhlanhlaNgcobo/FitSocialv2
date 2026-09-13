import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Decides, from scroll activity, whether the floating nav should be on screen.
///
/// Scrolling down through the feed drops the bar away; scrolling back up brings
/// it in. Split out of the shell so the rule can be exercised directly: it is
/// pure bookkeeping over a stream of notifications, and testing it through a
/// widget tree would only obscure it.
class NavVisibility {
  NavVisibility({this.flipDistance = 24});

  /// Distance the scroll must travel *consistently in one direction* before the
  /// state changes.
  ///
  /// A per-event threshold is not enough. A finger drag emits a stream of small
  /// deltas that routinely change sign, so any single-event test flips the bar
  /// back and forth several times a second — and each flip restarts the
  /// transition from wherever the previous one had reached. That thrash, rather
  /// than the animation itself, is what reads as lag. Accumulating gives one
  /// state change per real direction change.
  final double flipDistance;

  final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  /// Running total of movement since the last direction change.
  double _travel = 0;

  /// Feeds one notification in. Returns false always, so it can be handed
  /// straight to [NotificationListener.onNotification] without swallowing the
  /// notification from other listeners.
  bool handle(ScrollNotification notification) {
    // Horizontal strips — the Pulse tray, the badge row — must not drive the
    // bar; only the page's own vertical scroll should.
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;

      // A reversal starts a fresh run, so the threshold measures one continuous
      // movement rather than a net figure that never accumulates.
      if (delta.isNegative != _travel.isNegative) _travel = 0;
      _travel += delta;

      // At the very top there is nothing to get out of the way of.
      if (notification.metrics.pixels <= 0) {
        hidden.value = false;
      } else if (_travel > flipDistance) {
        hidden.value = true;
      } else if (_travel < -flipDistance) {
        hidden.value = false;
      }
    } else if (notification is ScrollEndNotification) {
      // Only the run resets, so the next gesture is measured from scratch. The
      // bar itself stays where the last direction put it: lifting your finger
      // part-way down the feed is not a request to see the nav again. It comes
      // back when — and only when — the user scrolls up.
      _travel = 0;
    }

    return false;
  }

  /// Puts the bar back on screen regardless of scroll history.
  ///
  /// Arriving on a new page is a fresh start: without this, leaving one branch
  /// scrolled down would land the user on the next one with no nav and no
  /// obvious way to get it back — a page that does not scroll would strand
  /// them there.
  void reveal() {
    _travel = 0;
    hidden.value = false;
  }

  void dispose() => hidden.dispose();
}

/// Carries the shell's [NavVisibility] down to whatever wants to move with it.
///
/// The nav capsule is handed its state directly, because the shell builds it.
/// The top bar is not: it belongs to whichever screen is showing, several
/// levels below, and the scroll that drives it is caught up here. Passing the
/// notifier rather than the value is the point — an [InheritedNotifier]
/// rebuilds only the widgets that read it, so a flip repaints the two bars and
/// leaves the branch stack between them alone.
class NavVisibilityScope extends InheritedNotifier<ValueListenable<bool>> {
  const NavVisibilityScope({
    required ValueListenable<bool> hidden,
    required super.child,
    super.key,
  }) : super(notifier: hidden);

  /// Whether the shell's bars are currently off screen.
  ///
  /// Defaults to visible where there is no scope — a screen pushed over the
  /// shell has no scroll signal reaching it, and a bar that hid itself there
  /// could never be brought back.
  static bool hiddenOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NavVisibilityScope>();
    return scope?.notifier?.value ?? false;
  }
}

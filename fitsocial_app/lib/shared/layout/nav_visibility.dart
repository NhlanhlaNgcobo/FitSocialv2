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

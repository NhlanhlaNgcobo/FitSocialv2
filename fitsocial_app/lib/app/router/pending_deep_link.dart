import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/links/share_links.dart';

/// Where a shared link wanted to go, held across whatever stands between the
/// tap and the screen.
///
/// Someone who taps a shared post while signed out — or on a cold start, before
/// the session has finished restoring — would otherwise land on the welcome
/// screen or the feed and never see the post they were sent. The router parks
/// the route here on the way past and redeems it once the app is ready for it.
///
/// Deliberately a plain mutable holder rather than a notifier: it is written
/// from inside `GoRouter.redirect`, which runs during navigation, and anything
/// that fired listeners from there would re-enter the router mid-flight.
class PendingDeepLink {
  String? _route;

  /// The route waiting to be redeemed, without consuming it.
  String? get route => _route;

  /// Parks [location] if it is somewhere a shared link can point.
  ///
  /// Filtered through [FitSocialLinks.isShareableRoute] so this can only ever
  /// hold a content route: it is replayed after sign-in, and an arbitrary
  /// remembered path would hand a crafted link control over where a new user
  /// lands.
  void remember(String location) {
    if (!FitSocialLinks.isShareableRoute(location)) return;
    _route = location;
  }

  // A tapped notification deliberately does NOT park itself here. Redeeming a
  // pending route is a redirect, which REPLACES the stack — fine for a shared
  // link, where arriving at the post with nothing behind it is what the user
  // asked for, but wrong for a notification, where the back button then leaves
  // the app instead of returning to the feed. PushTapRouter holds its own
  // destination and pushes it onto /home once there is a session.

  /// Returns the parked route and clears it, so a link is followed once.
  String? take() {
    final route = _route;
    _route = null;
    return route;
  }

  void clear() => _route = null;
}

/// One holder for the app. Read by the router; not watched, because its whole
/// job is to be read at the moment a redirect is decided.
final pendingDeepLinkProvider = Provider<PendingDeepLink>((ref) {
  return PendingDeepLink();
});

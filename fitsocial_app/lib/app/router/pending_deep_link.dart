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

  /// Parks the destination of a tapped push notification.
  ///
  /// Separate from [remember] only in which routes it will accept — see
  /// [FitSocialLinks.isPushRoute]. A notification can point at a challenge
  /// board, which is not a shareable link and so is not somewhere an incoming
  /// URL may send anyone.
  ///
  /// Needed for the cold-start case: tapping a notification for an app that is
  /// not running starts it at the splash screen, and the destination has to
  /// survive the session restoring before there is a router able to go there.
  void rememberPush(String location) {
    if (!FitSocialLinks.isPushRoute(location)) return;
    _route = location;
  }

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

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/pending_deep_link.dart';
import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../shared/links/share_links.dart';
import '../../auth/application/app_session.dart';

/// Where tapping a push notification takes you.
///
/// The destination is carried on the message as `data['route']`, computed by
/// functions/push.js from the same fields `FitNotification.route` reads. Nothing
/// is re-derived here: the phone is handed a path and its only job is to decide
/// whether it can go there yet.
///
/// Two arrivals, and they need different answers:
///
///   * the app was running and backgrounded — `onMessageOpenedApp`. The router
///     exists and the user is signed in, so go straight there.
///   * the app was not running — `getInitialMessage`. The app is on the splash
///     screen with a session still restoring, and there is nowhere to navigate
///     to yet. The route is parked in [PendingDeepLink], which the router
///     already redeems on its way off the splash — the same path a tapped
///     shared link takes.
class PushTapRouter {
  PushTapRouter(this._ref);

  final Ref _ref;

  StreamSubscription<RemoteMessage>? _taps;

  /// Begins listening, and handles the notification the app was launched by, if
  /// there was one.
  ///
  /// Safe to call more than once; the subscription is only made once.
  Future<void> start() async {
    if (!_ref.read(bootstrapStatusProvider).canUseFirebase) return;

    try {
      _taps ??= FirebaseMessaging.onMessageOpenedApp.listen(_open);

      // Answers null on a launch that was not a notification tap, which is
      // almost every launch.
      final launchedBy = await FirebaseMessaging.instance.getInitialMessage();
      if (launchedBy != null) _open(launchedBy);
    } catch (error) {
      // A phone that cannot tell us why it launched still has an app to run,
      // and the notification is in the inbox either way.
      debugPrint('Listening for notification taps failed: $error');
    }
  }

  void dispose() {
    _taps?.cancel();
    _taps = null;
  }

  void _open(RemoteMessage message) {
    final route = message.data['route'];
    // Empty is normal: push.js sends it for a notification whose destination id
    // was missing. Tapping that one just opens the app, which is the honest
    // outcome — there is nothing to show.
    if (route is! String || route.isEmpty) return;

    // Validated even though this app wrote it. The check costs nothing, and the
    // day a route reaches a phone from somewhere other than push.js is not the
    // day to discover that anything at all could be navigated to.
    if (!FitSocialLinks.isPushRoute(route)) {
      debugPrint('Ignoring a push route this app does not recognise: $route');
      return;
    }

    // Not signed in, or still restoring. Park it: the router redeems a pending
    // route when it leaves the splash and again after a sign-in, so the
    // destination survives whatever stands between the tap and a usable app.
    if (_ref.read(appSessionProvider).stage != AuthStage.authenticated) {
      _ref.read(pendingDeepLinkProvider).rememberPush(route);
      return;
    }

    _ref.read(appRouterProvider).go(route);
  }
}

final pushTapRouterProvider = Provider<PushTapRouter>((ref) {
  final router = PushTapRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});

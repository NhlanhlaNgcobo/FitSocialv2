import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../core/bootstrap/bootstrap_status.dart';
import '../../../shared/links/share_links.dart';
import '../../auth/application/app_session.dart';

/// Where tapping a push notification takes you.
///
/// The destination is carried on the message as `data['route']`, computed by
/// functions/push.js from the same fields `FitNotification.route` reads. Nothing
/// is re-derived here: the phone is handed a path and its only job is to decide
/// whether it can go there yet, and what should sit underneath it when it does.
///
/// That second part is the whole reason this is not one line. `/post/:postId`,
/// `/user/:userId` and `/challenge/board/:challengeId` are top-level routes,
/// siblings of the shell that holds `/home` rather than children of it. Sending
/// somebody straight to one with `go()` REPLACES the stack, so the post is the
/// only thing on it and the back button leaves the app instead of returning to
/// the feed. Everywhere else in the app reaches these screens with `push()`
/// from inside the shell, which is why only notifications behaved that way.
///
/// So: push, always, onto a `/home` that is known to be underneath.
class PushTapRouter {
  PushTapRouter(this._ref);

  final Ref _ref;

  StreamSubscription<RemoteMessage>? _taps;

  /// Where a tap wanted to go, held while the session is still restoring or
  /// while nobody is signed in yet.
  String? _waitingRoute;

  /// Listener on [AppSession] used only while [_waitingRoute] is set.
  ///
  /// Attached to the notifier directly rather than through `ref.listen`, which
  /// expects to be called while a provider is being built — this runs long
  /// after that, from a notification tap.
  VoidCallback? _sessionListener;

  /// Begins listening, and handles the notification the app was launched by, if
  /// there was one.
  ///
  /// Safe to call more than once; the subscription is only made once.
  Future<void> start() async {
    if (!_ref.read(bootstrapStatusProvider).canUseFirebase) return;

    try {
      _taps ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _open(message, wasRunning: true),
      );

      // Answers null on a launch that was not a notification tap, which is
      // almost every launch.
      final launchedBy = await FirebaseMessaging.instance.getInitialMessage();
      if (launchedBy != null) _open(launchedBy, wasRunning: false);
    } catch (error) {
      // A phone that cannot tell us why it launched still has an app to run,
      // and the notification is in the inbox either way.
      debugPrint('Listening for notification taps failed: $error');
    }
  }

  void dispose() {
    _taps?.cancel();
    _taps = null;
    _stopWaiting();
  }

  /// [wasRunning] separates a tap on a live app from one that launched it.
  ///
  /// It decides only what has to be underneath the destination: a running app
  /// already has the shell on screen and the user should come back to whatever
  /// they were looking at, while a cold start has nothing but the splash and
  /// needs `/home` put down first.
  void _open(RemoteMessage message, {required bool wasRunning}) {
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

    if (_ref.read(appSessionProvider).stage == AuthStage.authenticated) {
      _navigate(route, layHomeFirst: !wasRunning);
      return;
    }

    // Still restoring, or signed out at a welcome screen. Hold the destination
    // and open it once there is an app to open it in — which may be after a
    // whole sign-in.
    _waitForSession(route);
  }

  void _waitForSession(String route) {
    _waitingRoute = route;
    if (_sessionListener != null) return;

    final session = _ref.read(appSessionProvider);
    void onChanged() {
      if (session.stage != AuthStage.authenticated) return;
      final pending = _waitingRoute;
      _stopWaiting();
      // Home first: whatever the router settled on after sign-in, the
      // destination has to be pushed on top of something the back button can
      // return to.
      if (pending != null) _navigate(pending, layHomeFirst: true);
    }

    _sessionListener = onChanged;
    session.addListener(onChanged);
  }

  void _stopWaiting() {
    final listener = _sessionListener;
    if (listener != null) {
      // read, not watch: this is teardown, and the session outlives it.
      _ref.read(appSessionProvider).removeListener(listener);
    }
    _sessionListener = null;
    _waitingRoute = null;
  }

  /// Opens [route] with something to come back to.
  ///
  /// Deferred to after the frame because the two callers arrive mid-flight —
  /// one from a platform channel during startup, one from a session change that
  /// is itself about to make the router redirect. Navigating into a router that
  /// is still resolving its own redirect is how a destination gets silently
  /// replaced by the one the redirect had already decided on.
  void _navigate(String route, {required bool layHomeFirst}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = _ref.read(appRouterProvider);
      // Replaces the splash (or the welcome screen just signed out of) with the
      // feed, so the push below has a floor. Skipped when the app was already
      // running, so somebody reading their profile comes back to their profile
      // rather than being dropped on the feed.
      if (layHomeFirst) router.go('/home');
      router.push(route);
    });
  }
}

final pushTapRouterProvider = Provider<PushTapRouter>((ref) {
  final router = PushTapRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});

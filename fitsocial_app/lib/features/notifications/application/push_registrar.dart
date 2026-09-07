import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../data/push_preference_store.dart';
import '../data/push_token_store.dart';

/// This device's standing arrangement to be pushed to.
///
/// Deliberately not a stream or a provider the UI watches. Registration is a
/// side effect of signing in and signing out, not a piece of state anything
/// renders, and the one thing it must do reliably is happen in the right order
/// relative to the sign-out that follows it.
abstract class PushRegistrar {
  /// Registers this device against [userId], if the user has not turned push
  /// off. Safe to call again for a user who is already registered.
  ///
  /// Returns whether this device will now actually be pushed to. False covers
  /// three different disappointments — the preference is off, the operating
  /// system refused permission, FCM would not issue a token — and the caller
  /// that asked for this on purpose needs to know, because a switch that says
  /// "on" while Android is silently dropping every notification is worse than
  /// no switch.
  Future<bool> register(String userId);

  /// Withdraws whatever [register] last put in place.
  ///
  /// Takes no arguments on purpose: it registered the token, so it is the thing
  /// that knows which one to withdraw. A caller having to remember would be a
  /// caller that can get it wrong at exactly the moment — sign-out — where
  /// getting it wrong means the next person to use the phone receives somebody
  /// else's notifications.
  Future<void> unregister();
}

/// Used by builds with no Firebase behind them, and by tests.
///
/// Mirrors `NoopCrashReporter`: a const default that lets an [AppSession] be
/// built without a messaging stack under it.
class NoopPushRegistrar implements PushRegistrar {
  const NoopPushRegistrar();

  /// Always false — nothing was registered, because there is nothing to
  /// register with.
  @override
  Future<bool> register(String userId) async => false;

  @override
  Future<void> unregister() async {}
}

/// The real one.
///
/// Every method swallows its own failures. A token that could not be written is
/// a phone that will not buzz, which is a disappointment; a token that could not
/// be written turning into a thrown error on the sign-in path is a user who
/// cannot get into the app at all, which is not.
class FirebasePushRegistrar implements PushRegistrar {
  FirebasePushRegistrar({
    required FirebaseMessaging messaging,
    required PushTokenStore tokens,
    PushPreferenceStore preferences = const PushPreferenceStore(),
  })  : _messaging = messaging,
        _tokens = tokens,
        _preferences = preferences;

  final FirebaseMessaging _messaging;
  final PushTokenStore _tokens;
  final PushPreferenceStore _preferences;

  /// Who this device is currently registered for, and as what. Held so
  /// [unregister] can undo exactly what [register] did, including after a token
  /// refresh has replaced the one it started with.
  String? _userId;
  String? _token;

  StreamSubscription<String>? _refreshes;

  @override
  Future<bool> register(String userId) async {
    _userId = userId;

    try {
      if (!await _preferences.read()) return false;

      // Raises the Android 13+ POST_NOTIFICATIONS dialog itself, so there is no
      // permission_handler call to keep in step with it. Android shows that
      // dialog once ever; later calls resolve against the existing answer
      // without any UI, which is what makes calling this on every cold start
      // harmless.
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }

      final token = await _messaging.getToken();
      if (token == null) return false;

      await _tokens.save(userId, token, platform: defaultTargetPlatform.name);
      _token = token;

      // FCM reissues a token on its own schedule — a restore to a new phone, a
      // reinstall, a periodic rotation. Without this the old one keeps being
      // sent to and quietly failing until push.js prunes it, and this device
      // goes silent in the meantime.
      _refreshes ??= _messaging.onTokenRefresh.listen(_onTokenRefreshed);
      return true;
    } catch (error) {
      debugPrint('Registering for push failed: $error');
      return false;
    }
  }

  @override
  Future<void> unregister() async {
    final userId = _userId;
    final token = _token;

    // Cleared first, so a failure below cannot leave this thinking it is still
    // registered for somebody who has signed out.
    _userId = null;
    _token = null;
    await _refreshes?.cancel();
    _refreshes = null;

    try {
      if (userId != null && token != null) {
        await _tokens.remove(userId, token);
      }

      // Not just the document. The token is an address for this installation,
      // and leaving it live means the next account signed in here inherits an
      // address the previous account's notifications were already being sent
      // to. Deleting it forces FCM to issue a fresh one on the next register.
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('Unregistering from push failed: $error');
    }
  }

  Future<void> _onTokenRefreshed(String token) async {
    final userId = _userId;
    if (userId == null) return;

    final previous = _token;
    try {
      await _tokens.save(userId, token, platform: defaultTargetPlatform.name);
      _token = token;
      // The old document is dead the moment FCM stops honouring the old token,
      // and push.js would prune it on the next failed send. Removing it here
      // means the list stays honest without waiting for a notification that may
      // be days away.
      if (previous != null && previous != token) {
        await _tokens.remove(userId, previous);
      }
    } catch (error) {
      debugPrint('Saving a refreshed push token failed: $error');
    }
  }
}

/// The app's registrar.
///
/// A no-op when this build has no Firebase behind it, for the same reason the
/// notification repository falls back to an empty inbox: a backendless build
/// should still run.
final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (!status.canUseFirebase) return const NoopPushRegistrar();

  return FirebasePushRegistrar(
    messaging: FirebaseMessaging.instance,
    tokens: ref.watch(pushTokenStoreProvider),
    preferences: ref.watch(pushPreferenceStoreProvider),
  );
});

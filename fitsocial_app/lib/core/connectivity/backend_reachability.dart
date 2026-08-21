import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/app_session.dart';

/// Whether the app can currently reach its backend.
enum BackendReachability {
  online,
  offline,

  /// Not established — nobody is signed in, so nothing is listening.
  unknown,
}

/// How long a listener must keep serving from cache before that is reported as
/// being offline.
///
/// Firestore delivers the cached copy first and the server copy a moment
/// later, so *every* listener starts out from-cache even on a perfect
/// connection. Reporting that immediately would flash an offline banner on
/// every cold start.
const Duration kOfflineSettleDelay = Duration(seconds: 4);

/// Turns a stream of "was this served from cache" flags into reachability.
///
/// Going offline is delayed by [settleDelay]; coming back online is reported
/// at once. The asymmetry is deliberate — a false "offline" is a visible lie
/// on screen, while a slightly late one costs nothing.
///
/// Kept as a plain function over a plain stream so the timing can be tested
/// with fake clocks, without Firestore anywhere near it.
Stream<BackendReachability> reachabilityFromCacheFlags(
  Stream<bool> isFromCache, {
  Duration settleDelay = kOfflineSettleDelay,
}) {
  late StreamController<BackendReachability> controller;
  StreamSubscription<bool>? subscription;
  Timer? pendingOffline;
  BackendReachability? last;

  void emit(BackendReachability value) {
    if (value == last) return;
    last = value;
    controller.add(value);
  }

  void onFlag(bool fromCache) {
    if (!fromCache) {
      pendingOffline?.cancel();
      pendingOffline = null;
      emit(BackendReachability.online);
      return;
    }
    // Already waiting on an earlier from-cache event — let that timer run
    // rather than restarting the clock on every emission.
    pendingOffline ??= Timer(
      settleDelay,
      () => emit(BackendReachability.offline),
    );
  }

  controller = StreamController<BackendReachability>(
    onListen: () {
      subscription = isFromCache.listen(
        onFlag,
        // A listener that dies tells us nothing about the network, so the last
        // known state stands rather than being reported as offline.
        onError: (Object _) {},
        onDone: controller.close,
      );
    },
    onCancel: () async {
      pendingOffline?.cancel();
      await subscription?.cancel();
    },
  );

  return controller.stream;
}

/// Live reachability, watched off the signed-in user's own profile document.
///
/// That document rather than a dedicated ping: it always exists for a signed-in
/// user, it is already cached, and a metadata-only listener on it costs nothing
/// extra. There is no separate connectivity plugin here on purpose — what
/// matters is whether *Firestore* is reachable, and a phone can hold a wifi
/// association that routes nowhere.
final backendReachabilityProvider = StreamProvider<BackendReachability>((ref) {
  // Re-subscribes when the signed-in user changes.
  ref.watch(appSessionProvider);

  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) {
    return Stream.value(BackendReachability.unknown);
  }

  final flags = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) => snapshot.metadata.isFromCache);

  return reachabilityFromCacheFlags(flags);
});

/// Convenience for widgets that only care whether to show the offline state.
///
/// [BackendReachability.unknown] reads as online: before anything is
/// established there is nothing to warn about.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(backendReachabilityProvider).maybeWhen(
        data: (value) => value == BackendReachability.offline,
        orElse: () => false,
      );
});

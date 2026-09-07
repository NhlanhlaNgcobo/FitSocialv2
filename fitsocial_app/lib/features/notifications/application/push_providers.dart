import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main/application/content_providers.dart'
    show currentUserIdProvider;
import '../data/push_preference_store.dart';
import 'push_registrar.dart';

/// Whether this device is set to receive push notifications.
///
/// A future rather than a stream because there is nothing to watch: the only
/// thing that changes this is the switch below, which invalidates it. Callers
/// render `.valueOrNull ?? true` while it loads, matching the default the store
/// itself falls back to — so the switch never briefly shows the opposite of
/// what it is about to show.
final pushEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(pushPreferenceStoreProvider).read();
});

/// Turns push on or off for this device.
///
/// Returns whether notifications will now actually arrive. Enabling can come
/// back false — the operating system has its own switch, and someone who
/// refused the permission prompt (or turned FitSocial off in Android settings)
/// has said no in a place this app cannot overrule. The caller is expected to
/// say so rather than leave a switch claiming something untrue.
final pushPreferenceActionsProvider =
    Provider<Future<bool> Function({required bool enabled})>((ref) {
  return ({required bool enabled}) async {
    // Written before registering, not after: `PushRegistrar.register` reads
    // this preference and refuses when it is off, so a register called ahead of
    // the write would do nothing at all.
    await ref.read(pushPreferenceStoreProvider).write(enabled: enabled);

    final registrar = ref.read(pushRegistrarProvider);
    var registered = false;

    if (enabled) {
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) registered = await registrar.register(userId);
    } else {
      await registrar.unregister();
    }

    ref.invalidate(pushEnabledProvider);
    return enabled ? registered : true;
  };
});

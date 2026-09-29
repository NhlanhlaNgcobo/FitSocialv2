import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bootstrap/bootstrap_status.dart';

/// Features that ship dark and are switched on from the Firebase console.
///
/// Build 11 carries every one of these whether or not it is finished, and the
/// switch is what keeps an unfinished one out of testers' hands. Remote Config
/// rather than a `const bool` like `kMusicAccountsEnabled` because turning one
/// off — a leaderboard showing something it should not, an AI summary saying
/// something it should not — must not wait for a release to reach phones.
///
/// Every default is off. A phone that has never reached Remote Config (first
/// launch on a plane, a fetch that timed out) sees the app as it was before
/// Build 11, which is the one state already known to work.
///
/// The keys are the Remote Config parameter names. Renaming one orphans the
/// value set in the console, so they are fixed strings, not derived from the
/// enum name.
enum FeatureFlag {
  goalsChallenges('f1_goals_challenges'),
  weeklyInsights('f2_weekly_insights'),
  upNext('f3_up_next'),
  compare('f4_compare'),
  recapCards('f5_recap_cards'),
  leaderboards('f6_leaderboards');

  const FeatureFlag(this.key);

  final String key;
}

/// Numbers that are tuned from the console rather than the code.
///
/// The integrity ceilings are here because the right value is a judgement
/// that will move once real data arrives: 100,000 steps is a marathon and a
/// half, and somebody will eventually do it. The server reads the same
/// parameters (functions/remote_config.js), so the app's "excluded from
/// ranking" note and the ranking itself cannot disagree.
enum Tunable {
  maxDailySteps('integrity_max_daily_steps', 100000),
  // 24 hours. Anything above it is impossible rather than implausible.
  maxDailyActiveMinutes('integrity_max_daily_active_minutes', 1440);

  const Tunable(this.key, this.fallback);

  final String key;
  final int fallback;
}

/// A snapshot of every flag and tunable, as the app should act on them now.
@immutable
class FeatureFlags {
  const FeatureFlags({
    Map<FeatureFlag, bool> flags = const {},
    Map<Tunable, int> tunables = const {},
  })  : _flags = flags,
        _tunables = tunables;

  /// Reads a snapshot out of anything that answers by key. A tunable that
  /// comes back zero or negative is treated as unset: a ceiling of zero would
  /// exclude every step anybody has ever taken, and no console typo should be
  /// able to do that.
  factory FeatureFlags.read({
    required bool Function(String key) getBool,
    required int Function(String key) getInt,
  }) {
    return FeatureFlags(
      flags: {
        for (final flag in FeatureFlag.values) flag: getBool(flag.key),
      },
      tunables: {
        for (final tunable in Tunable.values)
          if (getInt(tunable.key) > 0) tunable: getInt(tunable.key),
      },
    );
  }

  /// Everything at its default: every feature off, every number at its
  /// fallback.
  static const defaults = FeatureFlags();

  final Map<FeatureFlag, bool> _flags;
  final Map<Tunable, int> _tunables;

  bool isOn(FeatureFlag flag) => _flags[flag] ?? false;

  int valueOf(Tunable tunable) => _tunables[tunable] ?? tunable.fallback;

  /// A copy with [flag] forced. Tests and a debug build use this; nothing in
  /// release does.
  FeatureFlags withFlag(FeatureFlag flag, bool on) =>
      FeatureFlags(flags: {..._flags, flag: on}, tunables: _tunables);

  /// The defaults Remote Config is seeded with, so a value missing from the
  /// console reads as off rather than as the SDK's own `false`/`0` — the same
  /// thing for flags, but not for tunables.
  static Map<String, Object> get remoteDefaults => {
        for (final flag in FeatureFlag.values) flag.key: false,
        for (final tunable in Tunable.values) tunable.key: tunable.fallback,
      };

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      mapEquals(other._flags, _flags) &&
      mapEquals(other._tunables, _tunables);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(_flags.entries.map((e) => (e.key, e.value))),
        Object.hashAllUnordered(
          _tunables.entries.map((e) => (e.key, e.value)),
        ),
      );
}

/// Seeds Remote Config and starts a fetch. Call once from the bootstrap.
///
/// Never awaited to completion: the fetch goes over the network and startup
/// must not wait on it — this is an app people open in basements and on
/// trails. Whatever was fetched last time is activated from disk straight
/// away, and a new fetch lands on [featureFlagsProvider]'s stream when it
/// arrives.
Future<void> initFeatureFlags() async {
  final config = FirebaseRemoteConfig.instance;
  await config.setDefaults(FeatureFlags.remoteDefaults);
  await config.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      // An hour in release. A developer flipping a flag in the console wants
      // to see it on the next launch, not the next hour.
      minimumFetchInterval:
          kDebugMode ? Duration.zero : const Duration(hours: 1),
    ),
  );
  _startupFetch = config.fetchAndActivate().catchError((_) => false);
}

/// The fetch [initFeatureFlags] started, completing with whether it activated
/// anything new. Held so the provider can re-read when it lands rather than
/// guessing how long a fetch takes.
Future<bool>? _startupFetch;

/// The live flag snapshot.
///
/// Emits what is active now, then again whenever a fetch activates new values
/// or the console pushes a real-time update. Without Firebase — widget tests,
/// a checkout with no `firebase_options.dart` — it is [FeatureFlags.defaults]
/// and never changes, so every Build 11 feature is simply absent.
final featureFlagsProvider = StreamProvider<FeatureFlags>((ref) async* {
  if (!ref.watch(bootstrapStatusProvider).canUseFirebase) {
    yield FeatureFlags.defaults;
    return;
  }

  final config = FirebaseRemoteConfig.instance;
  FeatureFlags snapshot() => FeatureFlags.read(
        getBool: config.getBool,
        getInt: config.getInt,
      );

  yield snapshot();

  final changes = StreamController<FeatureFlags>();
  final subscription = config.onConfigUpdated.listen(
    (_) async {
      try {
        await config.activate();
        changes.add(snapshot());
      } catch (_) {
        // The values in hand stay in force; the next update tries again.
      }
    },
    // The real-time channel is a nicety. Losing it costs nothing but latency:
    // the startup fetch still lands, and so does the next launch's.
    onError: (_) {},
  );
  ref.onDispose(() {
    subscription.cancel();
    changes.close();
  });

  // The startup fetch usually finishes after the first snapshot was taken.
  // Re-read when it lands, so a flag switched on in the console reaches this
  // session without waiting for a real-time push.
  unawaited(
    _startupFetch?.then((activated) {
      if (activated && !changes.isClosed) changes.add(snapshot());
    }),
  );

  yield* changes.stream.distinct();
});

/// Whether [flag] is on right now. False until the snapshot has loaded.
final featureEnabledProvider = Provider.family<bool, FeatureFlag>((ref, flag) {
  final flags = ref.watch(featureFlagsProvider).valueOrNull;
  return (flags ?? FeatureFlags.defaults).isOn(flag);
});

/// The current value of [tunable].
final tunableProvider = Provider.family<int, Tunable>((ref, tunable) {
  final flags = ref.watch(featureFlagsProvider).valueOrNull;
  return (flags ?? FeatureFlags.defaults).valueOf(tunable);
});

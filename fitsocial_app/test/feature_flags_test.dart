import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every feature is off by default', () {
    for (final flag in FeatureFlag.values) {
      expect(FeatureFlags.defaults.isOn(flag), isFalse, reason: flag.key);
    }
  });

  test('tunables fall back to their documented values', () {
    expect(FeatureFlags.defaults.valueOf(Tunable.maxDailySteps), 100000);
    expect(FeatureFlags.defaults.valueOf(Tunable.maxDailyActiveMinutes), 1440);
  });

  test('the Remote Config seed covers every key, flags off', () {
    final seed = FeatureFlags.remoteDefaults;
    for (final flag in FeatureFlag.values) {
      expect(seed[flag.key], false);
    }
    for (final tunable in Tunable.values) {
      expect(seed[tunable.key], tunable.fallback);
    }
  });

  test('read picks up flags and positive tunables', () {
    final flags = FeatureFlags.read(
      getBool: (key) => key == FeatureFlag.leaderboards.key,
      getInt: (key) => key == Tunable.maxDailySteps.key ? 80000 : 0,
    );
    expect(flags.isOn(FeatureFlag.leaderboards), isTrue);
    expect(flags.isOn(FeatureFlag.goalsChallenges), isFalse);
    expect(flags.valueOf(Tunable.maxDailySteps), 80000);
  });

  test('a zero or negative ceiling from the console is ignored', () {
    final flags = FeatureFlags.read(
      getBool: (_) => false,
      getInt: (key) => key == Tunable.maxDailySteps.key ? 0 : -1,
    );
    expect(flags.valueOf(Tunable.maxDailySteps), 100000);
    expect(flags.valueOf(Tunable.maxDailyActiveMinutes), 1440);
  });

  test('equal snapshots compare equal, so the stream does not re-emit', () {
    final a = FeatureFlags.defaults.withFlag(FeatureFlag.compare, true);
    final b = FeatureFlags.defaults.withFlag(FeatureFlag.compare, true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == FeatureFlags.defaults, isFalse);
  });

  test('flag keys match the server list in functions/remote_config.js', () {
    // The server keeps its own copy because a Cloud Function cannot import
    // Dart. If this list changes, change DEFAULTS there too.
    expect(FeatureFlag.values.map((f) => f.key), [
      'f1_goals_challenges',
      'f2_weekly_insights',
      'f3_up_next',
      'f4_compare',
      'f5_recap_cards',
      'f6_leaderboards',
    ]);
    expect(Tunable.values.map((t) => t.key), [
      'integrity_max_daily_steps',
      'integrity_max_daily_active_minutes',
    ]);
  });
}

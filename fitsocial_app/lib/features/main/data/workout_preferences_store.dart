import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/previous_performance.dart';

/// How the user likes a workout session to behave.
class WorkoutPreferences {
  const WorkoutPreferences({
    this.restSeconds = defaultRestSeconds,
    this.trackRpe = false,
    this.previousSource = PreviousSource.anyWorkout,
    this.includeWarmupsInStats = false,
    this.smartSupersetScroll = true,
    this.inlineTimer = true,
    this.livePrAlerts = true,
  });

  /// Ninety seconds: long enough for hypertrophy work, short enough that
  /// nobody doing heavy triples is surprised by it — they set their own.
  static const defaultRestSeconds = 90;

  /// The choices the settings picker offers. Zero is "off".
  static const restChoices = [0, 30, 60, 90, 120, 150, 180, 240, 300];

  /// Rest after each set, unless the exercise sets its own. Zero for no timer.
  final int restSeconds;

  /// Whether set rows show an RPE column. Off by default: most people do not
  /// rate their sets, and a column of dashes is noise to them.
  final bool trackRpe;

  /// Where the PREVIOUS column looks for last time.
  final PreviousSource previousSource;

  /// Whether warm-ups count in the volume figures shown. Display only:
  /// nothing stored changes, and records never use warm-ups either way.
  final bool includeWarmupsInStats;

  /// Ticking a set in a superset scrolls to the next exercise in it.
  final bool smartSupersetScroll;

  /// A stopwatch on timed sets, for holds timed as they are done.
  final bool inlineTimer;

  /// A toast and a buzz when a ticked set is a personal record.
  final bool livePrAlerts;

  WorkoutPreferences copyWith({
    int? restSeconds,
    bool? trackRpe,
    PreviousSource? previousSource,
    bool? includeWarmupsInStats,
    bool? smartSupersetScroll,
    bool? inlineTimer,
    bool? livePrAlerts,
  }) =>
      WorkoutPreferences(
        restSeconds: restSeconds ?? this.restSeconds,
        trackRpe: trackRpe ?? this.trackRpe,
        previousSource: previousSource ?? this.previousSource,
        includeWarmupsInStats:
            includeWarmupsInStats ?? this.includeWarmupsInStats,
        smartSupersetScroll: smartSupersetScroll ?? this.smartSupersetScroll,
        inlineTimer: inlineTimer ?? this.inlineTimer,
        livePrAlerts: livePrAlerts ?? this.livePrAlerts,
      );
}

/// Persists [WorkoutPreferences].
///
/// In [FlutterSecureStorage] for the reason `RunImportPreferenceStore` gives:
/// it is the key/value store the app already has wired into both platforms.
class WorkoutPreferencesStore {
  const WorkoutPreferencesStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String _restKey = 'workout_rest_seconds';
  static const String _rpeKey = 'workout_track_rpe';
  static const String _previousKey = 'workout_previous_source';
  static const String _warmupsKey = 'workout_include_warmups';
  static const String _supersetScrollKey = 'workout_superset_scroll';
  static const String _inlineTimerKey = 'workout_inline_timer';
  static const String _prAlertsKey = 'workout_pr_alerts';

  final FlutterSecureStorage _storage;

  /// Never throws; anything unreadable falls back to the defaults.
  Future<WorkoutPreferences> read() async {
    try {
      final rest = int.tryParse(await _storage.read(key: _restKey) ?? '');
      final rpe = await _storage.read(key: _rpeKey);
      // A switch never written reads as its default, not as off.
      Future<bool> flag(String key, {required bool fallback}) async =>
          switch (await _storage.read(key: key)) {
            'true' => true,
            'false' => false,
            _ => fallback,
          };
      return WorkoutPreferences(
        restSeconds: rest == null || rest < 0
            ? WorkoutPreferences.defaultRestSeconds
            : rest,
        trackRpe: rpe == 'true',
        previousSource:
            PreviousSource.fromName(await _storage.read(key: _previousKey)),
        includeWarmupsInStats: await flag(_warmupsKey, fallback: false),
        smartSupersetScroll: await flag(_supersetScrollKey, fallback: true),
        inlineTimer: await flag(_inlineTimerKey, fallback: true),
        livePrAlerts: await flag(_prAlertsKey, fallback: true),
      );
    } catch (_) {
      return const WorkoutPreferences();
    }
  }

  Future<void> write(WorkoutPreferences prefs) async {
    try {
      await _storage.write(key: _restKey, value: '${prefs.restSeconds}');
      await _storage.write(
        key: _rpeKey,
        value: prefs.trackRpe ? 'true' : 'false',
      );
      await _storage.write(
        key: _previousKey,
        value: prefs.previousSource.name,
      );
      await _storage.write(
        key: _warmupsKey,
        value: '${prefs.includeWarmupsInStats}',
      );
      await _storage.write(
        key: _supersetScrollKey,
        value: '${prefs.smartSupersetScroll}',
      );
      await _storage.write(key: _inlineTimerKey, value: '${prefs.inlineTimer}');
      await _storage.write(key: _prAlertsKey, value: '${prefs.livePrAlerts}');
    } catch (_) {
      // Holds for this session and is lost on relaunch, which beats blocking
      // the control on a keystore round trip.
    }
  }
}

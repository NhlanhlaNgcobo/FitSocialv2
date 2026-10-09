import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How the user likes a workout session to behave.
class WorkoutPreferences {
  const WorkoutPreferences({
    this.restSeconds = defaultRestSeconds,
    this.trackRpe = false,
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

  WorkoutPreferences copyWith({int? restSeconds, bool? trackRpe}) =>
      WorkoutPreferences(
        restSeconds: restSeconds ?? this.restSeconds,
        trackRpe: trackRpe ?? this.trackRpe,
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

  final FlutterSecureStorage _storage;

  /// Never throws; anything unreadable falls back to the defaults.
  Future<WorkoutPreferences> read() async {
    try {
      final rest = int.tryParse(await _storage.read(key: _restKey) ?? '');
      final rpe = await _storage.read(key: _rpeKey);
      return WorkoutPreferences(
        restSeconds: rest == null || rest < 0
            ? WorkoutPreferences.defaultRestSeconds
            : rest,
        trackRpe: rpe == 'true',
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
    } catch (_) {
      // Holds for this session and is lost on relaunch, which beats blocking
      // the control on a keystore round trip.
    }
  }
}

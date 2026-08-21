import 'package:health/health.dart';

/// Today's health metrics pulled from Health Connect (Android) /
/// HealthKit (iOS). Smartwatches (Galaxy Watch, Pixel Watch, Fitbit,
/// Garmin, …) sync their data into these platform stores, so reading them
/// covers wearable data without pairing directly to each watch brand.
class HealthSummary {
  const HealthSummary({
    required this.steps,
    required this.heartRateBpm,
    required this.sleep,
    required this.activeCaloriesKcal,
    required this.distanceKm,
    required this.available,
    this.readAt,
    this.stepsAsOf,
  });

  static const unavailable = HealthSummary(
    steps: null,
    heartRateBpm: null,
    sleep: null,
    activeCaloriesKcal: null,
    distanceKm: null,
    available: false,
  );

  final int? steps;
  final double? heartRateBpm; // most recent reading today
  final Duration? sleep; // last night's total sleep
  final double? activeCaloriesKcal;
  final double? distanceKm;

  /// False when Health Connect isn't installed / permissions denied.
  final bool available;

  /// When this summary was read. Null on [unavailable].
  final DateTime? readAt;

  /// End of the most recent step record Health Connect held for today.
  ///
  /// Apps write into Health Connect in batches rather than live — Samsung
  /// Health flushes on its own schedule — so the total here trails what their
  /// own screen shows by however long it has been since that last write. This
  /// is that moment, kept so a lagging number can be shown as "synced a few
  /// minutes ago" instead of reading as wrong. Null when nothing has been
  /// written today.
  final DateTime? stepsAsOf;
}

class HealthService {
  HealthService() : _health = Health();

  final Health _health;

  static const _types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.DISTANCE_DELTA,
  ];

  static final _readAccess =
      _types.map((_) => HealthDataAccess.READ).toList(growable: false);

  Future<void> configure() => _health.configure();

  /// Whether read access is already granted, without prompting.
  ///
  /// Null means undetermined — HealthKit will not disclose read grants on iOS,
  /// and it is also what a missing Health Connect install looks like. Callers
  /// should treat anything but true as "ask".
  Future<bool?> hasPermissions() async {
    try {
      await _health.configure();
      return await _health.hasPermissions(_types, permissions: _readAccess);
    } catch (_) {
      return false;
    }
  }

  /// Requests read access to the health data types we use.
  /// Returns false when the platform store is missing or the user declines.
  Future<bool> requestPermissions() async {
    try {
      await _health.configure();
      final granted = await _health.requestAuthorization(
        _types,
        permissions: _readAccess,
      );
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Health Connect's own de-duplicated step total for a window.
  ///
  /// Null when the store is unavailable or the read throws. Used for reading a
  /// day that has already ended, where [readTodaySummary]'s midnight-to-now
  /// window is the wrong question.
  Future<int?> readStepsBetween(DateTime start, DateTime end) async {
    try {
      await _health.configure();
      return await _health.getTotalStepsInInterval(start, end);
    } catch (_) {
      return null;
    }
  }

  /// Reads today's summary (and last night's sleep).
  Future<HealthSummary> readTodaySummary() async {
    try {
      await _health.configure();
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);

      final steps = await _health.getTotalStepsInInterval(midnight, now);

      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: midnight.subtract(const Duration(hours: 12)),
        endTime: now,
      );

      double? latestHr;
      DateTime? latestHrTime;
      DateTime? stepsAsOf;
      double activeKcal = 0;
      double distanceMeters = 0;
      Duration sleepTotal = Duration.zero;

      for (final p in points) {
        final value = p.value;
        switch (p.type) {
          case HealthDataType.HEART_RATE:
            if (value is NumericHealthValue &&
                (latestHrTime == null || p.dateTo.isAfter(latestHrTime))) {
              latestHr = value.numericValue.toDouble();
              latestHrTime = p.dateTo;
            }
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            if (value is NumericHealthValue && !p.dateFrom.isBefore(midnight)) {
              activeKcal += value.numericValue.toDouble();
            }
          case HealthDataType.DISTANCE_DELTA:
            if (value is NumericHealthValue && !p.dateFrom.isBefore(midnight)) {
              distanceMeters += value.numericValue.toDouble();
            }
          case HealthDataType.STEPS:
            // Only the freshness of the records is taken from here. The total
            // stays with getTotalStepsInInterval, which is Health Connect's own
            // de-duplicated aggregate — these raw records overlap across
            // sources and summing them would double-count phone against watch.
            if (!p.dateTo.isBefore(midnight) &&
                (stepsAsOf == null || p.dateTo.isAfter(stepsAsOf))) {
              stepsAsOf = p.dateTo;
            }
          case HealthDataType.SLEEP_SESSION:
            sleepTotal += p.dateTo.difference(p.dateFrom);
          default:
            break;
        }
      }

      return HealthSummary(
        steps: steps,
        heartRateBpm: latestHr,
        sleep: sleepTotal == Duration.zero ? null : sleepTotal,
        activeCaloriesKcal: activeKcal == 0 ? null : activeKcal,
        distanceKm: distanceMeters == 0 ? null : distanceMeters / 1000.0,
        available: true,
        readAt: DateTime.now(),
        stepsAsOf: stepsAsOf,
      );
    } catch (_) {
      return HealthSummary.unavailable;
    }
  }
}

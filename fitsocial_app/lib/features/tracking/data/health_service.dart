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

  Future<void> configure() => _health.configure();

  /// Requests read access to the health data types we use.
  /// Returns false when the platform store is missing or the user declines.
  Future<bool> requestPermissions() async {
    try {
      await _health.configure();
      final granted = await _health.requestAuthorization(
        _types,
        permissions:
            _types.map((_) => HealthDataAccess.READ).toList(growable: false),
      );
      return granted;
    } catch (_) {
      return false;
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
      );
    } catch (_) {
      return HealthSummary.unavailable;
    }
  }
}

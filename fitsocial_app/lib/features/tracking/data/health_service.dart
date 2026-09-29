import 'package:health/health.dart';

import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart';
import '../domain/imported_run.dart';
import '../domain/imported_workout.dart';
import 'run_import_service.dart';
import 'workout_prefill_service.dart';

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
    this.caloriesAreTotal = false,
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

  /// True when [activeCaloriesKcal] actually holds *total* energy, because the
  /// source writes only that. Total counts resting burn, so it runs several
  /// times higher -- the tile has to say which it is showing.
  final bool caloriesAreTotal;

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

class HealthService implements RunSessionSource, WorkoutSessionSource {
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

  /// Second-choice types, read only when the first choice came back empty.
  ///
  /// Watches disagree about which record to write for the same thing. Budget
  /// models commonly report TOTAL_CALORIES_BURNED and never
  /// ACTIVE_ENERGY_BURNED, and write sleep as bare stages with no SLEEP_SESSION
  /// wrapping them. Asking only for the first of each pair is why a watch that
  /// is plainly tracking calories and sleep can still leave both tiles empty.
  ///
  /// Kept out of [_types] on purpose: that list is the permission gate, and a
  /// user who declines one of these has not declined health access altogether.
  static const _fallbackTypes = <HealthDataType>[
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];

  /// What [readRunSessions] needs.
  ///
  /// Kept out of [_types] for the same reason the fallbacks are: that list is
  /// the permission gate, and somebody who wants their steps on the dashboard
  /// but does not want the app reading their watch's workouts has not declined
  /// health access. It is asked for, and the import simply finds nothing if it
  /// was refused.
  static const _importTypes = <HealthDataType>[HealthDataType.WORKOUT];

  /// Everything worth asking for: what the summary needs, plus the fallbacks,
  /// plus what importing runs needs. Every entry is declared in
  /// AndroidManifest.xml.
  static const _requestTypes = <HealthDataType>[
    ..._types,
    ..._fallbackTypes,
    ..._importTypes,
  ];

  static final _requestAccess =
      _requestTypes.map((_) => HealthDataAccess.READ).toList(growable: false);

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
        _requestTypes,
        permissions: _requestAccess,
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

  /// Steps somebody typed in by hand over a window. Null when unreadable.
  ///
  /// Summed from the raw records marked manual — Health Connect's recording
  /// method, HealthKit's "was user entered" — rather than asked for as
  /// `getTotalStepsInInterval(includeManualEntry: false)`. That call looks like
  /// the right one, but once any filter is set the plugin stops using Health
  /// Connect's de-duplicated aggregate and adds up raw records instead, which
  /// counts a walk twice when the phone and a paired watch both logged it.
  /// Manual entries have one source apiece and cannot overlap like that, so
  /// the sound figure is the de-duplicated total less these.
  Future<int?> readManualStepsBetween(DateTime start, DateTime end) async {
    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.STEPS],
        startTime: start,
        endTime: end,
      );
      var manual = 0;
      for (final point in points) {
        if (point.recordingMethod != RecordingMethod.manual) continue;
        final value = point.value;
        if (value is NumericHealthValue) {
          manual += value.numericValue.round();
        }
      }
      return manual;
    } catch (_) {
      return null;
    }
  }

  /// The largest single source's total, rather than every source added up.
  ///
  /// Once a watch is paired, the phone and the watch both report the same walk:
  /// the phone from its own sensors, the watch through its companion app. Added
  /// together they roughly double, and the more the phone is carried the worse
  /// it reads. Health Connect solves this for steps with
  /// [Health.getTotalStepsInInterval], its own de-duplicated aggregate -- there
  /// is no equivalent for calories, distance or sleep, so this stands in for it.
  ///
  /// Highest rather than first or newest: whichever source saw the most of the
  /// day is the one that missed the least of it. A phone left on a desk under-
  /// reports and loses to the watch; a watch taken off after lunch loses to the
  /// phone. It cannot exceed the true figure the way a sum can.
  static double _highestSource(Map<String, double> bySource) =>
      bySource.values.fold(0, (a, b) => b > a ? b : a);

  /// [_highestSource] for durations. Two apps both recording last night are
  /// describing one night's sleep, not two.
  static Duration _longestSource(Map<String, Duration> bySource) =>
      bySource.values.fold(Duration.zero, (a, b) => b > a ? b : a);

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
      // Keyed by source rather than summed, for every quantity that more
      // than one app can report. See [_highestSource].
      final activeBySource = <String, double>{};
      final totalKcalBySource = <String, double>{};
      final distanceBySource = <String, double>{};
      final sleepBySource = <String, Duration>{};
      final asleepBySource = <String, Duration>{};
      final stagesBySource = <String, Duration>{};

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
              activeBySource[p.sourceId] = (activeBySource[p.sourceId] ?? 0) +
                  value.numericValue.toDouble();
            }
          case HealthDataType.DISTANCE_DELTA:
            if (value is NumericHealthValue && !p.dateFrom.isBefore(midnight)) {
              distanceBySource[p.sourceId] =
                  (distanceBySource[p.sourceId] ?? 0) +
                      value.numericValue.toDouble();
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
            sleepBySource[p.sourceId] =
                (sleepBySource[p.sourceId] ?? Duration.zero) +
                    p.dateTo.difference(p.dateFrom);
          default:
            break;
        }
      }

      // Second pass, only for what the first came back empty on, and in its
      // own try: these types are outside the permission gate, so a refusal
      // throws here -- and that must not cost the caller the numbers the first
      // pass already found.
      final activeKcal = _highestSource(activeBySource);
      final distanceMeters = _highestSource(distanceBySource);
      final sleepTotal = _longestSource(sleepBySource);

      if (activeKcal == 0 || sleepTotal == Duration.zero) {
        try {
          final fallback = await _health.getHealthDataFromTypes(
            types: _fallbackTypes,
            startTime: midnight.subtract(const Duration(hours: 12)),
            endTime: now,
          );
          for (final p in fallback) {
            final value = p.value;
            switch (p.type) {
              case HealthDataType.TOTAL_CALORIES_BURNED:
                if (value is NumericHealthValue &&
                    !p.dateFrom.isBefore(midnight)) {
                  totalKcalBySource[p.sourceId] =
                      (totalKcalBySource[p.sourceId] ?? 0) +
                          value.numericValue.toDouble();
                }
              // ASLEEP is kept apart from the three stages rather than added
              // to them. A source that writes both is describing the same sleep
              // twice -- DEEP + LIGHT + REM is a breakdown of ASLEEP, not extra
              // hours on top of it -- and summing all four would report a night
              // roughly twice as long as it was.
              case HealthDataType.SLEEP_ASLEEP:
                asleepBySource[p.sourceId] =
                    (asleepBySource[p.sourceId] ?? Duration.zero) +
                        p.dateTo.difference(p.dateFrom);
              case HealthDataType.SLEEP_DEEP:
              case HealthDataType.SLEEP_LIGHT:
              case HealthDataType.SLEEP_REM:
                stagesBySource[p.sourceId] =
                    (stagesBySource[p.sourceId] ?? Duration.zero) +
                        p.dateTo.difference(p.dateFrom);
              default:
                break;
            }
          }
        } catch (_) {
          // Best-effort by definition. The first pass still stands.
        }
      }

      // Total energy includes resting burn, so it is several times the active
      // figure and cannot quietly stand in for it -- the flag travels with the
      // number so the tile can relabel itself rather than misreport it.
      final totalKcal = _highestSource(totalKcalBySource);
      final asleepTotal = _longestSource(asleepBySource);
      final stagesTotal = _longestSource(stagesBySource);

      final usingTotal = activeKcal == 0 && totalKcal > 0;
      final kcal = activeKcal != 0 ? activeKcal : totalKcal;
      // Preference order, most to least authoritative: a session the source
      // wrote itself, its own asleep total, then the stages added up.
      final sleep = sleepTotal != Duration.zero
          ? sleepTotal
          : asleepTotal != Duration.zero
              ? asleepTotal
              : stagesTotal;

      return HealthSummary(
        steps: steps,
        heartRateBpm: latestHr,
        sleep: sleep == Duration.zero ? null : sleep,
        activeCaloriesKcal: kcal == 0 ? null : kcal,
        caloriesAreTotal: usingTotal,
        distanceKm: distanceMeters == 0 ? null : distanceMeters / 1000.0,
        available: true,
        readAt: DateTime.now(),
        stepsAsOf: stepsAsOf,
      );
    } catch (_) {
      return HealthSummary.unavailable;
    }
  }

  // --- Importing runs recorded elsewhere --------------------------------
  //
  // A run recorded by a watch or by Samsung Health is invisible to this app
  // otherwise. These three reads are what turns one back into a draft: the
  // sessions themselves, a distance for the ones that did not carry their own,
  // and the heart rate over the window.
  //
  // Split into three rather than done in one pass on purpose. The session read
  // runs on every app resume and almost always finds nothing new; the other two
  // only run for a session that survived the duplicate checks, so the common
  // case costs exactly one query.

  /// Running sessions written to the platform store between [start] and [end].
  ///
  /// Only running: walks, rides and swims are somebody else's feature, and a
  /// run draft is a run. Treadmill sessions are included and flagged -- an
  /// indoor run is still a run, it just has no route, which is a shape the
  /// draft already supports.
  ///
  /// Returns empty on any failure, including a refused permission. There is
  /// nothing the caller could do differently and nothing the runner needs told:
  /// the feature's whole promise is that runs turn up on their own, so the
  /// honest failure is silence.
  /// The FitSocial activity behind a Health Connect workout type, or null for
  /// a workout this app has no way to record.
  ///
  /// RUNNING_TREADMILL maps to a run like any other: the difference is carried
  /// by [HealthRunRecord.isTreadmill], which is what explains the missing
  /// route, not by the activity kind.
  static ActivityKind? _activityKindFor(HealthWorkoutActivityType activity) {
    return switch (activity) {
      HealthWorkoutActivityType.RUNNING ||
      HealthWorkoutActivityType.RUNNING_TREADMILL =>
        ActivityKind.run,
      HealthWorkoutActivityType.WALKING => ActivityKind.walk,
      HealthWorkoutActivityType.HIKING => ActivityKind.hike,
      // BIKING is what Health Connect calls an outdoor ride; on iOS the same
      // constant is HealthKit's CYCLING. A stationary bike is
      // BIKING_STATIONARY and is deliberately not imported — it records no
      // distance worth filing as a ride.
      HealthWorkoutActivityType.BIKING => ActivityKind.ride,
      _ => null,
    };
  }

  /// Every exercise session in the window, with its workout payload.
  ///
  /// The one read behind both [readRunSessions] and [readWorkoutSessions];
  /// they differ only in which activities they keep and what they make of
  /// them. Throws on failure — the callers decide what silence looks like.
  Future<List<(HealthDataPoint, WorkoutHealthValue)>> _readWorkoutPoints({
    required DateTime start,
    required DateTime end,
  }) async {
    await _health.configure();
    final points = await _health.getHealthDataFromTypes(
      types: _importTypes,
      startTime: start,
      endTime: end,
    );
    return [
      for (final point in points)
        if (point.value case final WorkoutHealthValue value) (point, value),
    ];
  }

  @override
  Future<List<HealthRunRecord>> readRunSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final records = <HealthRunRecord>[];
      for (final (point, value)
          in await _readWorkoutPoints(start: start, end: end)) {
        final activity = value.workoutActivityType;
        final isTreadmill =
            activity == HealthWorkoutActivityType.RUNNING_TREADMILL;
        // The one place a third-party activity taxonomy is consulted.
        // Everything not named here — swims, rows, gym sessions — is left to
        // [readWorkoutSessions], because the drafts list can only offer back
        // sessions this app knows how to save as runs.
        final kind = _activityKindFor(activity);
        if (kind == null) continue;

        records.add(
          HealthRunRecord(
            externalId: point.uuid,
            startedAt: point.dateFrom,
            endedAt: point.dateTo,
            distanceMeters: _metersFrom(
              value.totalDistance,
              value.totalDistanceUnit,
            ),
            sourceId: point.sourceId,
            sourceName: point.sourceName,
            isTreadmill: isTreadmill,
            activityKind: kind,
          ),
        );
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  /// Gym-shaped sessions in the window: everything [readRunSessions] leaves
  /// behind. Strength work, HIIT, yoga, a rowing machine, a stationary bike.
  ///
  /// The complement rather than a second allow-list, so no activity can fall
  /// between the two readers: a session is either a run, a hike or a ride, or
  /// it is a workout. Walks land here too — there is no walk log, and a
  /// recorded walk is more use on the Training Log than nowhere.
  @override
  Future<List<HealthWorkoutRecord>> readWorkoutSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final records = <HealthWorkoutRecord>[];
      for (final (point, value)
          in await _readWorkoutPoints(start: start, end: end)) {
        final activity = value.workoutActivityType;
        if (_activityKindFor(activity) != null) continue;

        records.add(
          HealthWorkoutRecord(
            externalId: point.uuid,
            startedAt: point.dateFrom,
            endedAt: point.dateTo,
            activityName: workoutActivityName(activity),
            calories: _kilocaloriesFrom(
              value.totalEnergyBurned,
              value.totalEnergyBurnedUnit,
            ),
            sourceId: point.sourceId,
            sourceName: point.sourceName,
          ),
        );
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  /// Active energy recorded inside a window by one writer, in kilocalories.
  ///
  /// The calorie twin of [readDistanceMeters], with the same source
  /// restriction for the same reason. Null when nothing was recorded.
  @override
  Future<int?> readActiveCalories({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async {
    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: start,
        endTime: end,
      );

      var kcal = 0.0;
      for (final point in points) {
        if (point.sourceId != sourceId) continue;
        final value = point.value;
        if (value is! NumericHealthValue) continue;
        kcal += _kilocaloriesFrom(value.numericValue, point.unit) ?? 0;
      }
      return kcal > 0 ? kcal.round() : null;
    } catch (_) {
      return null;
    }
  }

  /// What a Health Connect activity type is called on a form.
  ///
  /// The enum names are shouted and underscored, and a few are mouthfuls no
  /// one says — "High intensity interval training" is HIIT to everyone who
  /// does it. Named overrides for those; the rest are the enum, humanised.
  static String workoutActivityName(HealthWorkoutActivityType activity) {
    const named = <HealthWorkoutActivityType, String>{
      HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING: 'HIIT',
      HealthWorkoutActivityType.STRENGTH_TRAINING: 'Strength training',
      HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING:
          'Strength training',
      HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING:
          'Functional training',
      HealthWorkoutActivityType.WEIGHTLIFTING: 'Weightlifting',
      HealthWorkoutActivityType.BIKING_STATIONARY: 'Indoor cycling',
      HealthWorkoutActivityType.ROWING_MACHINE: 'Rowing',
      HealthWorkoutActivityType.STAIR_CLIMBING_MACHINE: 'Stair climber',
      HealthWorkoutActivityType.WALKING_TREADMILL: 'Treadmill walk',
      HealthWorkoutActivityType.SWIMMING_POOL: 'Swimming',
      HealthWorkoutActivityType.SWIMMING_OPEN_WATER: 'Open water swim',
      HealthWorkoutActivityType.OTHER: 'Workout',
    };
    if (named[activity] case final name?) return name;
    final words = activity.name.toLowerCase().split('_');
    return words.first[0].toUpperCase() +
        words.first.substring(1) +
        (words.length > 1 ? ' ${words.skip(1).join(' ')}' : '');
  }

  /// Energy in kilocalories, whatever unit it arrived in. Null for nothing.
  static int? _kilocaloriesFrom(num? value, HealthDataUnit? unit) {
    if (value == null) return null;
    final amount = value.toDouble();
    final kcal = switch (unit) {
      HealthDataUnit.SMALL_CALORIE => amount / 1000,
      HealthDataUnit.JOULE => amount / 4184,
      // KILOCALORIE, LARGE_CALORIE, and the null a workout record gives.
      _ => amount,
    };
    return kcal.round();
  }

  /// Distance recorded inside a window, for a workout that carried none.
  ///
  /// Restricted to [sourceId] -- the app that wrote the workout. Every source
  /// covering the same run writes its own distance records, and adding them
  /// together would report a 5 km run as 10 km on any phone with a watch paired
  /// to it. Same reasoning as [_highestSource], applied where there is a right
  /// answer to pick rather than a guess to make.
  ///
  /// Null when nothing was recorded, which the caller must treat as "skip this
  /// session" rather than as zero.
  @override
  Future<double?> readDistanceMeters({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async {
    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.DISTANCE_DELTA],
        startTime: start,
        endTime: end,
      );

      var meters = 0.0;
      for (final point in points) {
        if (point.sourceId != sourceId) continue;
        final value = point.value;
        if (value is! NumericHealthValue) continue;
        meters += _metersFrom(value.numericValue, point.unit) ?? 0;
      }
      return meters > 0 ? meters : null;
    } catch (_) {
      return null;
    }
  }

  /// Heart rate across a session, in the shape a run already records.
  ///
  /// Coverage is the span from the first reading to the last rather than the
  /// number of readings: the point of the field is to say how much of the run
  /// the figure actually describes, and a watch that stopped reporting halfway
  /// through must not have its average read as covering the whole thing.
  ///
  /// Null when there is nothing usable, so an imported run with no heart rate
  /// looks the same as a run recorded without a strap.
  @override
  Future<HeartRateSummary?> readHeartRateSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      await _health.configure();
      final points = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.HEART_RATE],
        startTime: start,
        endTime: end,
      );

      var total = 0.0;
      var count = 0;
      var max = 0;
      DateTime? first;
      DateTime? last;

      for (final point in points) {
        final value = point.value;
        if (value is! NumericHealthValue) continue;
        final bpm = value.numericValue.toDouble();
        // The same plausibility window the strap recorder applies. A watch
        // writing a zero while it settles must not drag the average down.
        if (bpm < 25 || bpm > 240) continue;

        total += bpm;
        count += 1;
        if (bpm.round() > max) max = bpm.round();
        if (first == null || point.dateFrom.isBefore(first)) {
          first = point.dateFrom;
        }
        if (last == null || point.dateTo.isAfter(last)) last = point.dateTo;
      }

      if (count == 0 || first == null || last == null) return null;
      final coverage = last.difference(first);
      return HeartRateSummary(
        averageBpm: (total / count).round(),
        maxBpm: max,
        coverage: coverage.isNegative ? Duration.zero : coverage,
      );
    } catch (_) {
      return null;
    }
  }

  /// [value] in metres, or null when there is nothing to convert.
  ///
  /// A null unit is read as metres: that is what Health Connect stores distance
  /// in, and it is what the plugin reports when a record does not name one.
  static double? _metersFrom(num? value, HealthDataUnit? unit) {
    if (value == null) return null;
    final amount = value.toDouble();
    return switch (unit) {
      HealthDataUnit.MILE => amount * 1609.344,
      HealthDataUnit.YARD => amount * 0.9144,
      HealthDataUnit.FOOT => amount * 0.3048,
      HealthDataUnit.INCH => amount * 0.0254,
      HealthDataUnit.CENTIMETER => amount / 100,
      _ => amount,
    };
  }

  // --- Diagnostics ------------------------------------------------------
  //
  // Every read above collapses its failures into the same empty result: a
  // denied permission, a store with no data, and a read that threw are
  // indistinguishable once they reach the dashboard, where all three render as
  // "--". That is right for users and useless for working out why a particular
  // watch is only supplying some of its metrics. The methods below answer that
  // question directly, one type at a time.

  /// Types probed by [diagnose].
  ///
  /// Deliberately wider than [_types]: the point is to find out what the
  /// paired watch actually writes, including types the summary does not yet
  /// read. Every entry is backed by a permission already declared in
  /// AndroidManifest.xml, so a row that comes back ungranted means the user has
  /// not granted it -- not that the app forgot to ask for it.
  ///
  /// TOTAL_CALORIES_BURNED sits next to ACTIVE_ENERGY_BURNED, and the sleep
  /// stages next to SLEEP_SESSION, because budget watches commonly write one of
  /// each pair and not the other. WORKOUT is here to show whether importing
  /// runs recorded on the watch would have anything to read.
  static const _diagnosticTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.WORKOUT,
  ];

  static final _diagnosticAccess = _diagnosticTypes
      .map((_) => HealthDataAccess.READ)
      .toList(growable: false);

  /// Probes each type in [_diagnosticTypes] separately.
  ///
  /// One type per call, each in its own try, which is the whole point:
  /// [readTodaySummary] asks for five types in a single
  /// `getHealthDataFromTypes` and wraps the lot in one catch, so a single type
  /// that throws takes the other four down with it and reports nothing. Here a
  /// failure is attributed to the type that caused it.
  ///
  /// [window] defaults to a week rather than to today so that "this watch never
  /// writes this type" can be told apart from "nothing was recorded today" --
  /// the distinction that matters for sleep, where the watch may simply not
  /// have been worn last night. Seven days stays inside the 30-day limit Health
  /// Connect applies without READ_HEALTH_DATA_HISTORY, which is not declared.
  Future<List<HealthTypeDiagnostic>> diagnose({
    Duration window = const Duration(days: 7),
  }) async {
    // Not fatal, and deliberately not rethrown: if configure fails, every read
    // below fails too, and each row then carries the reason.
    try {
      await _health.configure();
    } catch (_) {}

    final now = DateTime.now();
    final start = now.subtract(window);
    final results = <HealthTypeDiagnostic>[];

    for (final type in _diagnosticTypes) {
      if (!_health.isDataTypeAvailable(type)) {
        results.add(HealthTypeDiagnostic(type: type, supported: false));
        continue;
      }

      bool? granted;
      try {
        granted = await _health.hasPermissions(
          [type],
          permissions: const [HealthDataAccess.READ],
        );
      } catch (_) {
        // Left null: undetermined is honest here. HealthKit never discloses
        // read grants, and a throw tells us nothing about the grant either.
      }

      var count = 0;
      final sources = <String>{};
      DateTime? latest;
      String? error;

      try {
        final points = await _health.getHealthDataFromTypes(
          types: [type],
          startTime: start,
          endTime: now,
        );
        count = points.length;
        for (final p in points) {
          if (p.sourceName.isNotEmpty) sources.add(p.sourceName);
          if (latest == null || p.dateTo.isAfter(latest)) latest = p.dateTo;
        }
      } catch (e) {
        error = e.toString();
      }

      results.add(
        HealthTypeDiagnostic(
          type: type,
          granted: granted,
          recordCount: count,
          sources: sources,
          latest: latest,
          error: error,
        ),
      );
    }

    return results;
  }

  /// Asks for read access to every type in [_diagnosticTypes].
  ///
  /// Separate from [requestPermissions], which covers only the five types the
  /// summary reads. A type the user was never asked about reports ungranted,
  /// which would otherwise look identical to one they refused -- and that is
  /// exactly the ambiguity the diagnostic exists to remove.
  Future<bool> requestDiagnosticPermissions() async {
    try {
      await _health.configure();
      return await _health.requestAuthorization(
        _diagnosticTypes,
        permissions: _diagnosticAccess,
      );
    } catch (_) {
      return false;
    }
  }
}

/// What one health data type looks like from the app's side, right now.
///
/// Kept separate from [HealthSummary]: that models the numbers a user is shown,
/// this models why they might be missing.
class HealthTypeDiagnostic {
  const HealthTypeDiagnostic({
    required this.type,
    this.supported = true,
    this.granted,
    this.recordCount = 0,
    this.sources = const {},
    this.latest,
    this.error,
  });

  final HealthDataType type;

  /// False when the platform store has no equivalent for this type at all.
  final bool supported;

  /// Null means undetermined -- HealthKit will not disclose read grants, and a
  /// permission check that threw says nothing either way.
  final bool? granted;

  /// Records returned over the probe window. Zero with [granted] true and no
  /// [error] is the interesting case: access is fine, nothing is writing.
  final int recordCount;

  /// Apps that wrote the records, from `HealthDataPoint.sourceName` -- the
  /// watch's companion app, the phone, or both.
  final Set<String> sources;

  /// End of the most recent record found, or null when there were none.
  final DateTime? latest;

  /// The read's exception, kept rather than swallowed.
  final String? error;

  /// Short, human-readable verdict for this row.
  String get verdict {
    if (!supported) return 'not supported on this platform';
    if (error != null) return 'read failed';
    if (granted == false) return 'permission not granted';
    if (recordCount == 0) {
      return granted == null ? 'no data (grant undetermined)' : 'no data';
    }
    return '$recordCount record${recordCount == 1 ? '' : 's'}';
  }

  /// True when nothing stands in the way and data is arriving.
  bool get isHealthy => supported && error == null && recordCount > 0;
}

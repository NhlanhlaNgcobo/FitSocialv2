import 'package:flutter/foundation.dart';

import '../../main/domain/activity_kind.dart';

/// The tuning that differs between one GPS activity and another.
///
/// Everything in [LiveRunService] was tuned around a person on foot: a top
/// speed of about 43 km/h, a stride to learn, a stationary threshold set just
/// under walking pace. Most of that survives a hike unchanged and none of it
/// survives a bicycle. This holds the numbers that have to move, so the service
/// keeps one code path instead of growing a branch per activity.
///
/// These are physics, not presentation: nothing here describes how an activity
/// looks. Icons, colours and labels live on [ActivityDescriptor] instead, so
/// that retuning a threshold and restyling a tile stay separate edits.
///
/// Named `GpsActivityProfile` rather than anything shorter because `geolocator`
/// already exports `ActivityType`, and [LiveRunService] — the one file that
/// needs this most — imports it.
@immutable
class GpsActivityProfile {
  const GpsActivityProfile({
    required this.kind,
    required this.teleportMaxSpeed,
    required this.driftRejectSpeed,
    required this.autoPauseSpeed,
    required this.minSegmentMeters,
    required this.usesStepFusion,
    required this.notificationTitle,
    required this.notificationText,
  });

  final ActivityKind kind;

  /// Above this speed (m/s) a fix is a GPS teleport and is thrown away.
  ///
  /// The old fixed 12 m/s is 43 km/h — comfortably above any sprint, and
  /// comfortably *below* a bicycle on a descent, where it would have silently
  /// discarded every legitimate fix and quietly shortened the ride.
  final double teleportMaxSpeed;

  /// Below this speed (m/s) a segment is treated as stationary drift and
  /// contributes no distance.
  ///
  /// Split from [autoPauseSpeed], which used to be the same constant. They read
  /// alike but do different jobs, and a hike needs one lowered without the
  /// other: dropping the drift threshold as well would start crediting the
  /// metre-scale wander of a phone standing still as real distance.
  final double driftRejectSpeed;

  /// Below this speed (m/s) the moving-time clock stops.
  ///
  /// Lower for a hike than for a run. A steep uphill scramble is genuinely
  /// slower than 0.6 m/s, and pausing the clock on the hardest part of a hike
  /// is precisely wrong.
  final double autoPauseSpeed;

  /// The shortest segment worth counting, in metres. Larger for faster
  /// activities, where a fix arrives having already covered real ground and a
  /// short chord is far more likely to be noise than movement.
  final double minSegmentMeters;

  /// Whether pedometer steps may top up a GPS segment and teach the stride.
  ///
  /// False for rides, and not merely as an optimisation. On a bicycle the step
  /// count is near zero while the distance is large, so leaving this on would
  /// both under-credit the ride and — because the stride calibrator is shared
  /// across the whole app session — teach an absurd metres-per-step figure that
  /// then corrupts the *next run's* distance.
  final bool usesStepFusion;

  /// What the lock-screen foreground-service notification says. A cyclist
  /// should not be told they have a run in progress for two hours.
  final String notificationTitle;
  final String notificationText;

  static const run = GpsActivityProfile(
    kind: ActivityKind.run,
    teleportMaxSpeed: 12,
    driftRejectSpeed: 0.6,
    autoPauseSpeed: 0.6,
    minSegmentMeters: 4,
    usesStepFusion: true,
    notificationTitle: 'FitSocial — run in progress',
    notificationText: 'Tracking your distance, time and route.',
  );

  static const walk = GpsActivityProfile(
    kind: ActivityKind.walk,
    teleportMaxSpeed: 12,
    driftRejectSpeed: 0.6,
    // ~1.4 km/h. A stroll is slower than a run's stationary threshold, and a
    // walk should not pause itself every time the pace eases off; the drift
    // threshold above still rejects standing still.
    autoPauseSpeed: 0.4,
    minSegmentMeters: 4,
    usesStepFusion: true,
    notificationTitle: 'FitSocial — walk in progress',
    notificationText: 'Tracking your distance, time and route.',
  );

  static const hike = GpsActivityProfile(
    kind: ActivityKind.hike,
    teleportMaxSpeed: 12,
    driftRejectSpeed: 0.6,
    // ~1.3 km/h. Slow enough to keep the clock running up a steep pitch, while
    // the drift threshold above still rejects the distance from standing still.
    autoPauseSpeed: 0.35,
    minSegmentMeters: 4,
    usesStepFusion: true,
    notificationTitle: 'FitSocial — hike in progress',
    notificationText: 'Tracking your distance, time and route.',
  );

  static const ride = GpsActivityProfile(
    kind: ActivityKind.ride,
    // 90 km/h. High enough for any descent a bicycle will see, still low enough
    // to catch the kind of jump a lost-and-reacquired fix produces.
    teleportMaxSpeed: 25,
    // ~3.6 km/h. A bicycle below walking pace is stopped, or being pushed.
    driftRejectSpeed: 1.0,
    autoPauseSpeed: 1.0,
    // A bike covers more ground between fixes, so a short chord is noise.
    minSegmentMeters: 8,
    usesStepFusion: false,
    notificationTitle: 'FitSocial — ride in progress',
    notificationText: 'Tracking your distance, time and route.',
  );

  /// The profile for [kind], falling back to [run].
  ///
  /// A workout never reaches here — it has no GPS — but returning the run
  /// profile is the safe answer if one ever does.
  static GpsActivityProfile forKind(ActivityKind kind) => switch (kind) {
        ActivityKind.walk => walk,
        ActivityKind.run => run,
        ActivityKind.hike => hike,
        ActivityKind.ride => ride,
        ActivityKind.workout => run,
      };
}

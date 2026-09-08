import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

/// What a logged session is.
///
/// The three GPS kinds all live in the `runs` collection and share one document
/// shape — a route, a distance, a duration. `activityType` on the document is
/// what tells them apart, and a document with no such field is a [run], because
/// that is every run logged before the field existed. Absence is the migration;
/// nothing was backfilled.
///
/// [workout] is the odd one out: a form, in its own collection, with no route
/// and no GPS. [ActivityKindX.isGps] is the line between them, and it is the
/// test to reach for rather than `!= workout` or `== run`.
enum ActivityKind { run, hike, ride, workout }

extension ActivityKindX on ActivityKind {
  /// Whether this kind is recorded by following the user around: a route, a
  /// distance, a live screen.
  ///
  /// Prefer this over comparing against [ActivityKind.run]. Every `== run`
  /// check written when there were only two kinds now silently excludes hikes
  /// and rides, and because nothing in the app switches exhaustively over this
  /// enum, the compiler will not tell you which ones you missed.
  bool get isGps => this != ActivityKind.workout;

  /// How this kind is written to Firestore and to on-device draft files.
  String get wireName => name;

  /// Reads a stored value back, treating anything unrecognised as a run.
  ///
  /// Tolerant on purpose, in both directions. A missing value is a legacy run.
  /// An unknown one is a document written by a newer build than this one — a
  /// kind we have not heard of yet — and degrading it to a run keeps the
  /// session visible rather than dropping it on the floor.
  static ActivityKind fromWire(Object? value) {
    if (value is! String) return ActivityKind.run;
    for (final kind in ActivityKind.values) {
      if (kind.wireName == value) return kind;
    }
    return ActivityKind.run;
  }
}

/// Rough energy cost of running one kilometre, in kcal.
///
/// The usual approximation is about 1 kcal per kg of body mass per km, which
/// puts a typical adult near this figure. Body mass is not something the app
/// asks for, so this stands in — and every calorie it produces is flagged as
/// an estimate rather than shown as a measurement.
///
/// Do not move this number. Calories are worked out when a session is read,
/// never stored on the document, so changing it does not affect future runs —
/// it silently re-values every run in the user's history.
const kcalPerKilometre = 60;

/// Everything the UI needs to know about one kind of activity, in one place.
///
/// This exists because the run/workout pair used to be hardcoded as a ternary
/// in six different widgets. Two of those would have rendered a hike as a
/// dumbbell, and neither would have failed to compile. One descriptor, read by
/// all of them, is what stops that happening again.
@immutable
class ActivityDescriptor {
  const ActivityDescriptor._({
    required this.kind,
    required this.singular,
    required this.plural,
    required this.icon,
    required this.accent,
    required this.usesPace,
    required this.kcalPerKm,
    required this.kcalPerHour,
  });

  final ActivityKind kind;

  /// "Run", "Hike", "Ride", "Workout". Used for session titles and for the
  /// `activity` label written onto a shared post.
  final String singular;
  final String plural;

  final IconData icon;

  /// A fixed hue in both themes, identifying the activity the way a brand
  /// colour does. Always read through `palette.accent()` before painting, or it
  /// will glare on the light theme.
  final Color accent;

  /// Whether the headline second metric is a pace (min/km) or a speed (km/h).
  ///
  /// False for rides only. A cyclist does not think in minutes per kilometre,
  /// and a 2:00 /km pace label is unreadable as a description of a bike.
  final bool usesPace;

  /// Energy per kilometre, in kcal. Zero when this kind is costed by time
  /// instead — see [kcalPerHour].
  final int kcalPerKm;

  /// Energy per hour, in kcal. Zero when this kind is costed by distance.
  final int kcalPerHour;

  static const _run = ActivityDescriptor._(
    kind: ActivityKind.run,
    singular: 'Run',
    plural: 'Runs',
    icon: Icons.directions_run_rounded,
    accent: Color(0xFF2ECBFF),
    usesPace: true,
    kcalPerKm: kcalPerKilometre,
    kcalPerHour: 0,
  );

  static const _hike = ActivityDescriptor._(
    kind: ActivityKind.hike,
    singular: 'Hike',
    plural: 'Hikes',
    icon: Icons.hiking_rounded,
    // Green, a shade off the meal accent: outdoors, and not a road run.
    accent: Color(0xFF5BC46A),
    usesPace: true,
    // Walking costs a little less per kilometre than running does. Climb would
    // push it back up, which is one of the things elevation gain is for.
    kcalPerKm: 55,
    kcalPerHour: 0,
  );

  static const _ride = ActivityDescriptor._(
    kind: ActivityKind.ride,
    singular: 'Ride',
    plural: 'Rides',
    icon: Icons.directions_bike_rounded,
    accent: Color(0xFFFFC24B),
    usesPace: false,
    // Costed by time, not distance. Cycling energy goes almost entirely into
    // air drag, so it scales with speed rather than with kilometres: a 40 km
    // descent and a 40 km climb are not the same ride, and no per-kilometre
    // constant can tell them apart. Roughly a moderate effort.
    kcalPerKm: 0,
    kcalPerHour: 480,
  );

  static const _workout = ActivityDescriptor._(
    kind: ActivityKind.workout,
    singular: 'Workout',
    plural: 'Workouts',
    icon: Icons.fitness_center_rounded,
    accent: AppColors.orangeBright,
    usesPace: false,
    // Neither. A workout's calories are typed in by the user.
    kcalPerKm: 0,
    kcalPerHour: 0,
  );

  static ActivityDescriptor of(ActivityKind kind) => switch (kind) {
        ActivityKind.run => _run,
        ActivityKind.hike => _hike,
        ActivityKind.ride => _ride,
        ActivityKind.workout => _workout,
      };

  /// The three kinds offered by the GPS tracker, in the order they are shown.
  static const List<ActivityKind> gpsKinds = [
    ActivityKind.run,
    ActivityKind.hike,
    ActivityKind.ride,
  ];
}

extension ActivityKindDescriptorX on ActivityKind {
  ActivityDescriptor get descriptor => ActivityDescriptor.of(this);
}

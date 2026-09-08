import '../../main/domain/activity_kind.dart';
import '../../main/domain/app_models.dart';
import 'run_draft.dart';
import 'run_pace.dart';

/// A stretch of time a run occupied.
///
/// Used to ask whether a session read out of Health Connect is the same outing
/// as a run FitSocial already has, which is a question about overlapping
/// windows and nothing else — the two records will not agree on distance,
/// duration or start time to the second, so comparing those would find
/// differences that are not there.
class RunWindow {
  const RunWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);

  /// How much of [other] and this window are the same wall-clock time.
  Duration overlapWith(RunWindow other) {
    final start = this.start.isAfter(other.start) ? this.start : other.start;
    final end = this.end.isBefore(other.end) ? this.end : other.end;
    final overlap = end.difference(start);
    return overlap.isNegative ? Duration.zero : overlap;
  }

  /// Whether these are the same outing recorded twice.
  ///
  /// Measured against the *shorter* window rather than against either one in
  /// particular: a watch and a phone recording the same run routinely disagree
  /// by a minute at each end, and a watch session wholly inside a longer phone
  /// session is still the same run. Half is a wide margin on purpose — the
  /// cost of a false match is one run the runner has to record again, and the
  /// cost of a miss is the same run counted twice in their stats forever.
  bool isSameOutingAs(RunWindow other) {
    final shorter = length.compareTo(other.length) <= 0 ? length : other.length;
    if (shorter <= Duration.zero) return false;
    return overlapWith(other) * 2 >= shorter;
  }
}

/// One running session as Health Connect describes it.
///
/// Everything here comes straight off a `HealthDataType.WORKOUT` data point.
/// [distanceMeters] is nullable because it genuinely often is: budget watches
/// and treadmill sessions frequently write a workout with no distance on it.
class HealthRunRecord {
  const HealthRunRecord({
    required this.externalId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.sourceId,
    required this.sourceName,
    required this.isTreadmill,
    this.activityKind = ActivityKind.run,
  });

  /// The Health Connect record uuid. The one stable handle on a session, and
  /// what the import ledger is keyed by.
  final String externalId;

  final DateTime startedAt;
  final DateTime endedAt;

  /// Metres, as the workout record reported them. Null when it did not.
  final double? distanceMeters;

  /// The package that wrote the session. Used to keep a distance fallback
  /// reading from the same writer that recorded the workout, rather than
  /// mixing in a second app's view of the same run.
  final String sourceId;

  /// The app that wrote the session — "Samsung Health", "Fitbit". Shown to the
  /// runner, so a draft they did not create has a name attached to it.
  final String sourceName;

  /// A treadmill session. Kept because it explains the missing route: an
  /// indoor run has nowhere to have been.
  final bool isTreadmill;

  /// Which activity Health Connect said this was. Defaults to a run, which is
  /// what every session imported before hikes and rides was.
  final ActivityKind activityKind;

  Duration get elapsed => endedAt.difference(startedAt);

  RunWindow get window => RunWindow(start: startedAt, end: endedAt);

  /// A session with a duration that could not be real.
  ///
  /// Zero-length records show up when a workout is started and cancelled.
  /// Anything past a day is a record whose end was never written — importing
  /// it would produce a run with an absurd pace.
  bool get hasImplausibleDuration =>
      elapsed <= Duration.zero || elapsed > const Duration(days: 1);

  /// The draft this session becomes.
  ///
  /// [distanceKm] is passed in rather than read off [distanceMeters] because
  /// the caller is the one that resolved it — a workout with no distance of
  /// its own is filled in from the distance records inside its window.
  ///
  /// `shareToFeed` is false and not negotiable here: nobody chose to publish
  /// this run, and the same reasoning that makes a draft with a missing flag
  /// private applies with more force to a run the app went looking for.
  RunDraft toDraft({
    required String id,
    required DateTime savedAt,
    required double distanceKm,
    HeartRateSummary? heartRate,
  }) {
    return RunDraft(
      id: id,
      savedAt: savedAt,
      distanceKm: distanceKm,
      elapsed: elapsed,
      averagePace: formatPaceOrSpeed(
        kind: activityKind,
        distanceKm: distanceKm,
        elapsed: elapsed,
      ),
      shareToFeed: false,
      activityKind: activityKind,
      // Empty, always. Health Connect keeps a route on an ExerciseRoute record
      // that needs its own permission and its own per-session consent prompt,
      // and the `health` package does not surface it — so an imported run has
      // the same shape as a treadmill run: real numbers, no line.
      routePoints: const [],
      startedAt: startedAt,
      heartRate: heartRate,
      source: RunDraftSource.healthConnect,
      externalId: externalId,
    );
  }
}

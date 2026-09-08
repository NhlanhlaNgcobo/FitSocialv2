import 'package:uuid/uuid.dart';

import '../../main/domain/app_models.dart';
import '../domain/imported_run.dart';
import '../domain/run_draft.dart';

/// The slice of the platform health store the import actually needs.
///
/// [HealthService] implements it; the import depends on this instead so a test
/// can stand in three methods rather than the whole store. Same reasoning as
/// the publish callback on `RunDraftController` — a narrow contract is the one
/// worth injecting.
abstract interface class RunSessionSource {
  Future<List<HealthRunRecord>> readRunSessions({
    required DateTime start,
    required DateTime end,
  });

  Future<double?> readDistanceMeters({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  });

  Future<HeartRateSummary?> readHeartRateSummary({
    required DateTime start,
    required DateTime end,
  });
}

/// Turns running sessions recorded elsewhere into drafts.
///
/// FitSocial only ever knew about a run if somebody opened the app and tapped
/// start. A run recorded on a watch, or by Samsung Health while the phone was
/// in a pocket, was simply lost. This reads those sessions back out of the
/// platform store and files each one as a draft — the same shape an offline run
/// takes, waiting on the same tap.
///
/// Nothing here writes to Firestore or to disk. It hands back drafts; the
/// caller decides what to do with them.
class RunImportService {
  RunImportService({required RunSessionSource health, Uuid uuid = const Uuid()})
      : _health = health,
        _uuid = uuid;

  final RunSessionSource _health;
  final Uuid _uuid;

  /// How far back each scan reaches.
  ///
  /// A fixed trailing window rather than "everything since last time", because
  /// Health Connect is not written live — Samsung Health flushes in batches, so
  /// a run that finished an hour ago is routinely not there yet, and the last
  /// stretch of an evening's running usually lands after the phone has been put
  /// down. A cursor would step past a session that had not arrived when it
  /// moved. Rescanning costs nothing because the ledger absorbs it.
  ///
  /// Two days rather than more: it only has to be longer than the longest
  /// plausible gap between finishing a run and opening the app, and every hour
  /// past that is a wider window to read on every single resume.
  static const Duration scanWindow = Duration(hours: 48);

  /// The floor a run has to clear to be worth filing, matching what the live
  /// run screen already refuses to save.
  static const double minimumDistanceKm = 0.05;

  /// The sessions worth importing, given what has already been dealt with.
  ///
  /// Pure, and separated from the reads for that reason: this is where every
  /// decision about duplicates is made, and it is the part that has to be
  /// right. It can be tested with a list and two sets, no platform store
  /// involved.
  ///
  /// [handled] is the union of the import ledger and the external ids of drafts
  /// already sitting on disk. Keeping the drafts in it means a ledger that
  /// failed to write, or was lost with the app's data, still cannot produce a
  /// second draft for a session already waiting in the list.
  ///
  /// [knownRuns] are the windows of runs the user already has in FitSocial. If
  /// they ran with the app open, Samsung Health recorded the same outing from
  /// the phone's own sensors, and importing it would count one run twice —
  /// forever, in their totals and their streak.
  ///
  /// Deliberately blind to the activity kind, now that hikes and rides import
  /// too. Two overlapping sessions of genuinely different activities are close
  /// to unheard of; two writers disagreeing about what one outing *was* is not
  /// — Samsung Health will happily call a trail run a hike. Matching on kind
  /// as well would let that pair through as two sessions, and a duplicate is
  /// the worse failure: a missed import can be entered by hand, an inflated
  /// streak cannot be taken back.
  static List<HealthRunRecord> selectImportable({
    required List<HealthRunRecord> records,
    required Set<String> handled,
    required List<RunWindow> knownRuns,
  }) {
    final selected = <HealthRunRecord>[];
    // Grows as we go: two sources writing the same run produce two sessions
    // with different uuids, and the second must be measured against the first
    // rather than only against what FitSocial already had.
    final claimed = [...knownRuns];

    // Oldest first, so when two records describe the same outing the earlier
    // one wins deterministically rather than by whatever order the store
    // happened to return.
    final ordered = [...records]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    for (final record in ordered) {
      if (handled.contains(record.externalId)) continue;
      if (record.hasImplausibleDuration) continue;
      if (claimed.any(record.window.isSameOutingAs)) continue;

      selected.add(record);
      claimed.add(record.window);
    }
    return selected;
  }

  /// Reads the store and returns a draft for every run worth offering.
  ///
  /// The order matters for cost. The session read runs on every resume and
  /// almost always comes back with nothing new, so the duplicate checks happen
  /// before the distance and heart-rate reads — on a normal resume this is one
  /// query and no further work.
  Future<List<RunDraft>> collect({
    required Set<String> handled,
    required List<RunWindow> knownRuns,
    DateTime? now,
  }) async {
    final end = now ?? DateTime.now();
    final records = await _health.readRunSessions(
      start: end.subtract(scanWindow),
      end: end,
    );
    if (records.isEmpty) return const [];

    final importable = selectImportable(
      records: records,
      handled: handled,
      knownRuns: knownRuns,
    );

    final drafts = <RunDraft>[];
    for (final record in importable) {
      final distanceKm = await _resolveDistanceKm(record);
      // No distance and none to be found: skipped rather than filed as a
      // timed run of unknown length. A draft the runner cannot check against
      // what their watch told them is worse than no draft at all — and the
      // ledger is deliberately not stamped, so it will be reconsidered once
      // the distance records catch up.
      if (distanceKm == null || distanceKm < minimumDistanceKm) continue;

      drafts.add(
        record.toDraft(
          id: _uuid.v4(),
          savedAt: DateTime.now(),
          distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
          heartRate: await _health.readHeartRateSummary(
            start: record.startedAt,
            end: record.endedAt,
          ),
        ),
      );
    }
    return drafts;
  }

  /// The workout's own distance, or the distance records inside its window.
  ///
  /// Budget watches and treadmill sessions commonly write a workout with no
  /// distance on it while still writing the distance records that make it up,
  /// so the fallback is the difference between importing those runs and losing
  /// them. Steps are deliberately not used as a third fallback: a stride
  /// estimate for a run nobody watched happen is a number, not a measurement.
  Future<double?> _resolveDistanceKm(HealthRunRecord record) async {
    final own = record.distanceMeters;
    if (own != null && own > 0) return own / 1000.0;

    final measured = await _health.readDistanceMeters(
      start: record.startedAt,
      end: record.endedAt,
      sourceId: record.sourceId,
    );
    return measured == null ? null : measured / 1000.0;
  }
}

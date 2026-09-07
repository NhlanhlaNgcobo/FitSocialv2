import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/tracking/data/run_import_service.dart';
import 'package:fitsocial_app/features/tracking/domain/imported_run.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in the three reads the import makes. The real [HealthService] is a
/// platform channel and none of it is what these tests are about.
class _FakeSource implements RunSessionSource {
  _FakeSource({
    this.sessions = const [],
    this.distanceMeters,
    this.heartRate,
  });

  final List<HealthRunRecord> sessions;
  final double? distanceMeters;
  final HeartRateSummary? heartRate;

  int distanceReads = 0;
  int heartRateReads = 0;
  DateTime? readFrom;
  DateTime? readTo;

  @override
  Future<List<HealthRunRecord>> readRunSessions({
    required DateTime start,
    required DateTime end,
  }) async {
    readFrom = start;
    readTo = end;
    return sessions;
  }

  @override
  Future<double?> readDistanceMeters({
    required DateTime start,
    required DateTime end,
    required String sourceId,
  }) async {
    distanceReads += 1;
    return distanceMeters;
  }

  @override
  Future<HeartRateSummary?> readHeartRateSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    heartRateReads += 1;
    return heartRate;
  }
}

HealthRunRecord record({
  String id = 'session-1',
  required DateTime startedAt,
  Duration length = const Duration(minutes: 30),
  double? distanceMeters = 5000,
  String sourceId = 'com.samsung.health',
  bool isTreadmill = false,
}) {
  return HealthRunRecord(
    externalId: id,
    startedAt: startedAt,
    endedAt: startedAt.add(length),
    distanceMeters: distanceMeters,
    sourceId: sourceId,
    sourceName: 'Samsung Health',
    isTreadmill: isTreadmill,
  );
}

void main() {
  final morning = DateTime(2026, 9, 6, 7);

  group('selectImportable', () {
    test('takes a session nothing else knows about', () {
      final selected = RunImportService.selectImportable(
        records: [record(startedAt: morning)],
        handled: const {},
        knownRuns: const [],
      );

      expect(selected, hasLength(1));
      expect(selected.single.externalId, 'session-1');
    });

    test('skips a session the ledger has already dealt with', () {
      final selected = RunImportService.selectImportable(
        records: [record(startedAt: morning)],
        handled: const {'session-1'},
        knownRuns: const [],
      );

      expect(selected, isEmpty);
    });

    test('skips a session overlapping a run FitSocial already has', () {
      // The same outing: the runner started FitSocial a minute after their
      // watch, and Samsung Health recorded the phone's version of it too.
      final selected = RunImportService.selectImportable(
        records: [record(startedAt: morning)],
        handled: const {},
        knownRuns: [
          RunWindow(
            start: morning.add(const Duration(minutes: 1)),
            end: morning.add(const Duration(minutes: 29)),
          ),
        ],
      );

      expect(selected, isEmpty);
    });

    test('keeps a session that merely touches the end of a known run', () {
      // Cooling down and starting again is two runs, not one recorded twice.
      final selected = RunImportService.selectImportable(
        records: [record(startedAt: morning.add(const Duration(minutes: 28)))],
        handled: const {},
        knownRuns: [
          RunWindow(
              start: morning, end: morning.add(const Duration(minutes: 30))),
        ],
      );

      expect(selected, hasLength(1));
    });

    test('two sources describing one outing yield one import', () {
      final selected = RunImportService.selectImportable(
        records: [
          record(id: 'phone', startedAt: morning),
          record(
            id: 'watch',
            startedAt: morning.add(const Duration(minutes: 2)),
            length: const Duration(minutes: 26),
          ),
        ],
        handled: const {},
        knownRuns: const [],
      );

      expect(selected, hasLength(1));
      // Oldest first, so the winner is deterministic rather than whatever the
      // store happened to hand back first.
      expect(selected.single.externalId, 'phone');
    });

    test('skips a session with no plausible duration', () {
      final selected = RunImportService.selectImportable(
        records: [
          record(id: 'cancelled', startedAt: morning, length: Duration.zero),
          record(
            id: 'never-ended',
            startedAt: morning,
            length: const Duration(days: 3),
          ),
        ],
        handled: const {},
        knownRuns: const [],
      );

      expect(selected, isEmpty);
    });
  });

  group('collect', () {
    test('maps a session onto a private, routeless draft', () async {
      final source = _FakeSource(
        sessions: [record(startedAt: morning)],
        heartRate: const HeartRateSummary(
          averageBpm: 148,
          maxBpm: 171,
          coverage: Duration(minutes: 28),
        ),
      );

      final drafts = await RunImportService(health: source).collect(
        handled: const {},
        knownRuns: const [],
      );

      expect(drafts, hasLength(1));
      final draft = drafts.single;
      expect(draft.distanceKm, 5.0);
      expect(draft.elapsed, const Duration(minutes: 30));
      expect(draft.averagePace, '6:00 /km');
      expect(draft.startedAt, morning);
      expect(draft.source, RunDraftSource.healthConnect);
      expect(draft.externalId, 'session-1');
      expect(draft.isImported, isTrue);
      // Nobody asked for this run to be published.
      expect(draft.shareToFeed, isFalse);
      // Health Connect keeps the route behind its own permission.
      expect(draft.routePoints, isEmpty);
      expect(draft.heartRate?.averageBpm, 148);
    });

    test('scans a trailing window rather than since a cursor', () async {
      final source = _FakeSource();
      final now = DateTime(2026, 9, 7, 18);

      await RunImportService(health: source)
          .collect(handled: const {}, knownRuns: const [], now: now);

      expect(source.readTo, now);
      expect(source.readFrom, now.subtract(RunImportService.scanWindow));
    });

    test('falls back to the distance records when the workout has none',
        () async {
      final source = _FakeSource(
        sessions: [record(startedAt: morning, distanceMeters: null)],
        distanceMeters: 4200,
      );

      final drafts = await RunImportService(health: source)
          .collect(handled: const {}, knownRuns: const []);

      expect(source.distanceReads, 1);
      expect(drafts.single.distanceKm, 4.2);
    });

    test('skips a session with no distance anywhere', () async {
      final source = _FakeSource(
        sessions: [record(startedAt: morning, distanceMeters: null)],
      );

      final drafts = await RunImportService(health: source)
          .collect(handled: const {}, knownRuns: const []);

      // Not filed as a timed run of unknown length, and not stamped either —
      // it gets reconsidered once the distance records catch up.
      expect(drafts, isEmpty);
    });

    test('skips a session under the distance floor', () async {
      final source = _FakeSource(
        sessions: [record(startedAt: morning, distanceMeters: 20)],
      );

      final drafts = await RunImportService(health: source)
          .collect(handled: const {}, knownRuns: const []);

      expect(drafts, isEmpty);
    });

    test('costs one read when there is nothing new', () async {
      final source = _FakeSource(sessions: [record(startedAt: morning)]);

      final drafts = await RunImportService(health: source)
          .collect(handled: const {'session-1'}, knownRuns: const []);

      expect(drafts, isEmpty);
      // The duplicate checks run before the distance and heart-rate reads, so
      // the common resume does no further work.
      expect(source.distanceReads, 0);
      expect(source.heartRateReads, 0);
    });

    test('imports a treadmill session, without a route', () async {
      final source = _FakeSource(
        sessions: [
          record(startedAt: morning, isTreadmill: true, distanceMeters: 3000),
        ],
      );

      final drafts = await RunImportService(health: source)
          .collect(handled: const {}, knownRuns: const []);

      expect(drafts.single.distanceKm, 3.0);
      expect(drafts.single.routePoints, isEmpty);
    });
  });
}

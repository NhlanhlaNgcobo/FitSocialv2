import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/tracking/data/live_run_service.dart';
import 'package:fitsocial_app/features/tracking/data/run_checkpoint_store.dart';

// The checkpoint is what stands between an OS kill mid-run and a lost run, so
// what matters here is that it survives a round trip intact, that a damaged
// one reads as "nothing to recover" rather than crashing a launch, and that
// restoring it does not change how the clock behaves afterwards.

void main() {
  final startedAt = DateTime.utc(2026, 8, 31, 6, 30);

  RunCheckpoint checkpoint({
    DateTime? savedAt,
    double distanceMeters = 5200,
    List<RunPoint>? points,
    bool isPaused = false,
  }) {
    return RunCheckpoint(
      startedAt: startedAt,
      savedAt: savedAt ?? DateTime.utc(2026, 8, 31, 7),
      distanceMeters: distanceMeters,
      movingElapsed: const Duration(minutes: 28, seconds: 14),
      isPaused: isPaused,
      points: points ??
          [
            RunPoint(
              latitude: -26.2041,
              longitude: 28.0473,
              timestamp: startedAt,
            ),
            RunPoint(
              latitude: -26.2045,
              longitude: 28.0480,
              timestamp: startedAt.add(const Duration(seconds: 5)),
            ),
          ],
    );
  }

  RunCheckpoint? roundTrip(RunCheckpoint c) =>
      RunCheckpoint.fromJson(jsonDecode(jsonEncode(c.toJson())));

  group('round trip', () {
    test('keeps everything the run is rebuilt from', () {
      final restored = roundTrip(checkpoint())!;

      expect(restored.startedAt, startedAt);
      expect(restored.distanceMeters, 5200);
      expect(restored.distanceKm, closeTo(5.2, 1e-9));
      expect(restored.movingElapsed, const Duration(minutes: 28, seconds: 14));
      expect(restored.isPaused, isFalse);
    });

    // The timestamps are kept because the rolling pace needs them after a
    // restore — a point encoded without one would silently break it.
    test('keeps the trace, timestamps and all', () {
      final restored = roundTrip(checkpoint())!;

      expect(restored.points, hasLength(2));
      expect(restored.points.first.latitude, closeTo(-26.2041, 1e-9));
      expect(restored.points.first.timestamp, startedAt);
      expect(
        restored.points.last.timestamp,
        startedAt.add(const Duration(seconds: 5)),
      );
    });

    test('keeps a paused run paused', () {
      expect(roundTrip(checkpoint(isPaused: true))!.isPaused, isTrue);
    });
  });

  group('fromJson refuses rather than throws', () {
    test('on nothing usable', () {
      expect(RunCheckpoint.fromJson(null), isNull);
      expect(RunCheckpoint.fromJson('nope'), isNull);
      expect(RunCheckpoint.fromJson(<String, dynamic>{}), isNull);
    });

    test('on a version it does not know', () {
      final future = checkpoint().toJson()..['v'] = 99;
      expect(RunCheckpoint.fromJson(future), isNull);
    });

    test('on missing essentials', () {
      for (final key in ['startedAt', 'savedAt', 'distanceMeters']) {
        final damaged = checkpoint().toJson()..remove(key);
        expect(RunCheckpoint.fromJson(damaged), isNull, reason: 'missing $key');
      }
    });

    test('but drops only the bad point out of a trace', () {
      final damaged =
          jsonDecode(jsonEncode(checkpoint().toJson())) as Map<String, dynamic>;
      (damaged['points'] as List)[0] = ['north', 28.0, 1];

      expect(RunCheckpoint.fromJson(damaged)!.points, hasLength(1));
    });
  });

  group('what is worth offering back', () {
    test('a checkpoint older than six hours is stale', () {
      final old = checkpoint(
        savedAt: DateTime.now().subtract(const Duration(hours: 6, minutes: 1)),
      );
      expect(old.isStale, isTrue);
    });

    test('one just inside six hours is not', () {
      final recent = checkpoint(
        savedAt: DateTime.now().subtract(const Duration(hours: 5, minutes: 59)),
      );
      expect(recent.isStale, isFalse);
    });

    // The run screen discards anything under 50 m. A checkpoint below that is
    // not a run somebody lost, and offering it back on every launch is noise.
    test('a run under fifty metres is not worth recovering', () {
      expect(checkpoint(distanceMeters: 30).isWorthRecovering, isFalse);
      expect(checkpoint(distanceMeters: 800).isWorthRecovering, isTrue);
    });

    test('nor is one with no real trace', () {
      expect(checkpoint(points: const []).isWorthRecovering, isFalse);
    });
  });

  group('the file', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('run_ckpt_test'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    FileRunCheckpointStore store() => FileRunCheckpointStore(
          rootDirectory: () async => root,
          userId: 'u1',
        );

    test('reads back nothing when none was ever written', () async {
      expect(await store().read(), isNull);
    });

    test('round trips through disk', () async {
      final s = store();
      await s.write(checkpoint());

      final restored = await s.read();
      expect(restored, isNotNull);
      expect(restored!.distanceMeters, 5200);
      expect(restored.points, hasLength(2));
    });

    // The writes are chained precisely so the twenty-second timer and the
    // write that fires as the app is backgrounded cannot tear each other's
    // file in half.
    test('back-to-back writes leave the later one, whole', () async {
      final s = store();

      await Future.wait([
        s.write(checkpoint(distanceMeters: 1000)),
        s.write(checkpoint(distanceMeters: 2000)),
      ]);

      final restored = await s.read();
      expect(restored, isNotNull);
      expect(restored!.distanceMeters, 2000);
    });

    test('clear leaves nothing to recover', () async {
      final s = store();
      await s.write(checkpoint());

      await s.clear();

      expect(await s.read(), isNull);
    });

    test('a truncated file reads as nothing rather than throwing', () async {
      final s = store();
      await s.write(checkpoint());
      File('${root.path}/run_drafts/u1/in_progress.json')
          .writeAsStringSync('{"v":1,"startedAt":"2026');

      expect(await s.read(), isNull);
    });
  });

  group('restoring the clock', () {
    const grace = Duration(seconds: 3);
    late DateTime now;

    setUp(() => now = DateTime(2026, 8, 31, 7));
    void advance(Duration by) => now = now.add(by);

    MovingTimeClock restored(Duration accrued) => MovingTimeClock(
          idleGrace: grace,
          now: () => now,
          accrued: accrued,
        );

    test('opens at the time the dead run had already banked', () {
      expect(
        restored(const Duration(minutes: 12)).elapsed,
        const Duration(minutes: 12),
      );
    });

    // The whole reason the open stretch is not restored: the process was dead
    // for that time and nobody was running.
    test('does not count the time the app was gone', () {
      final clock = restored(const Duration(minutes: 12));

      advance(const Duration(minutes: 40));
      clock.settle();

      expect(clock.elapsed, const Duration(minutes: 12));
      expect(clock.isIdle, isTrue);
    });

    test('picks straight back up when the runner moves again', () {
      final clock = restored(const Duration(minutes: 12));

      clock.markMovement();
      advance(const Duration(seconds: 30));
      clock.markMovement();
      clock.settle();

      expect(clock.elapsed, const Duration(minutes: 12, seconds: 30));
      expect(clock.isIdle, isFalse);
    });

    // A restored clock has to auto-pause on exactly the same rule as a fresh
    // one, or recovery would quietly invent a second kind of pause.
    test('auto-pauses on the same rule as a fresh clock', () {
      final clock = restored(const Duration(minutes: 12));

      clock.markMovement();
      advance(const Duration(seconds: 10));
      clock.settle();

      expect(clock.isIdle, isTrue);
      // Only the grace period counts, not the full ten seconds of standing.
      expect(clock.elapsed, const Duration(minutes: 12) + grace);
    });

    test('reset without an accrued time still starts at zero', () {
      final clock = restored(const Duration(minutes: 12))..reset();
      expect(clock.elapsed, Duration.zero);
    });
  });
}

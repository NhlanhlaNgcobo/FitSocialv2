import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/tracking/domain/run_draft.dart';

// A draft is the only copy of a run that never reached the server, so the
// round trip through disk is the thing worth pinning down: what survives it,
// and what a damaged file is allowed to cost.

RunDraft _draft({
  List<RoutePoint> route = const [],
  DateTime? startedAt,
  String? photoPath,
  bool photoUnavailable = false,
  HeartRateSummary? heartRate,
  DateTime? publishAttemptedAt,
  bool shareToFeed = true,
}) {
  return RunDraft(
    id: 'draft-1',
    savedAt: DateTime.utc(2026, 8, 31, 9, 15),
    distanceKm: 5.2,
    elapsed: const Duration(minutes: 28, seconds: 14),
    averagePace: '5:26 /km',
    shareToFeed: shareToFeed,
    routePoints: route,
    startedAt: startedAt,
    photoPath: photoPath,
    photoUnavailable: photoUnavailable,
    heartRate: heartRate,
    publishAttemptedAt: publishAttemptedAt,
  );
}

/// Through real JSON text, not just the map — encoding is where a type that
/// cannot be serialized would actually show up.
RunDraft? _roundTrip(RunDraft draft) {
  return RunDraft.fromJson(jsonDecode(jsonEncode(draft.toJson())));
}

void main() {
  group('RunDraft round trip', () {
    test('keeps the numbers a run is judged by', () {
      final restored = _roundTrip(_draft())!;

      expect(restored.id, 'draft-1');
      expect(restored.savedAt, DateTime.utc(2026, 8, 31, 9, 15));
      expect(restored.distanceKm, 5.2);
      expect(restored.elapsed, const Duration(minutes: 28, seconds: 14));
      expect(restored.averagePace, '5:26 /km');
      expect(restored.shareToFeed, isTrue);
    });

    test('keeps the route', () {
      final restored = _roundTrip(_draft(route: const [
        RoutePoint(latitude: -26.2041, longitude: 28.0473),
        RoutePoint(latitude: -26.2045, longitude: 28.0480),
      ]))!;

      expect(restored.routePoints, hasLength(2));
      expect(restored.routePoints.first.latitude, closeTo(-26.2041, 1e-9));
      expect(restored.routePoints.last.longitude, closeTo(28.0480, 1e-9));
    });

    // The treadmill shape. An empty route has to survive as an empty route
    // rather than becoming null somewhere and blowing up the card that draws
    // it.
    test('keeps an empty route empty', () {
      expect(_roundTrip(_draft())!.routePoints, isEmpty);
    });

    test('keeps heart rate when a strap was worn', () {
      final restored = _roundTrip(_draft(
        heartRate: const HeartRateSummary(
          averageBpm: 148,
          maxBpm: 171,
          coverage: Duration(minutes: 26),
        ),
      ))!;

      expect(restored.heartRate?.averageBpm, 148);
      expect(restored.heartRate?.maxBpm, 171);
      expect(restored.heartRate?.coverage, const Duration(minutes: 26));
    });

    // Omitted rather than stored as zeros, so a run without a strap reads the
    // same as every run logged before straps existed.
    test('omits heart rate when there was none', () {
      expect(_draft().toJson().containsKey('heartRate'), isFalse);
      expect(_roundTrip(_draft())!.heartRate, isNull);
    });

    test('keeps startedAt and the photo path', () {
      final restored = _roundTrip(_draft(
        startedAt: DateTime.utc(2026, 8, 31, 8, 40),
        photoPath: '/data/run_drafts/u1/draft-1.jpg',
      ))!;

      expect(restored.startedAt, DateTime.utc(2026, 8, 31, 8, 40));
      expect(restored.photoPath, '/data/run_drafts/u1/draft-1.jpg');
    });

    test('keeps the publish stamp that guards against a double post', () {
      final restored = _roundTrip(
        _draft(publishAttemptedAt: DateTime.utc(2026, 8, 31, 10)),
      )!;

      expect(restored.publishAttemptedAt, DateTime.utc(2026, 8, 31, 10));
      expect(restored.mayHavePublished, isTrue);
    });

    test('a draft that was never published carries no stamp', () {
      expect(_roundTrip(_draft())!.mayHavePublished, isFalse);
    });
  });

  group('RunDraft.fromJson refuses rather than throws', () {
    // One corrupt file on disk must cost one draft, never the whole list —
    // the same contract RoutePoint.fromMap and HeartRateSummary.fromMap keep.
    test('on nothing usable', () {
      expect(RunDraft.fromJson(null), isNull);
      expect(RunDraft.fromJson('not a draft'), isNull);
      expect(RunDraft.fromJson(<String, dynamic>{}), isNull);
    });

    test('on a version it does not know', () {
      final future = _draft().toJson()..['v'] = 99;
      expect(RunDraft.fromJson(future), isNull);
    });

    test('on a missing id, date, distance or duration', () {
      for (final key in [
        'id',
        'savedAt',
        'distanceKm',
        'durationSeconds',
      ]) {
        final damaged = _draft().toJson()..remove(key);
        expect(RunDraft.fromJson(damaged), isNull, reason: 'missing $key');
      }
    });

    test('on an unparseable date', () {
      final damaged = _draft().toJson()..['savedAt'] = 'the other day';
      expect(RunDraft.fromJson(damaged), isNull);
    });

    test('but drops only the bad coordinate out of a route', () {
      // Damaged after a decode rather than in the freshly-built map, because
      // that is the shape a file actually comes back as — untyped, and free to
      // hold a string where a number belongs.
      final damaged = jsonDecode(jsonEncode(_draft(route: const [
        RoutePoint(latitude: -26.2041, longitude: 28.0473),
        RoutePoint(latitude: -26.2045, longitude: 28.0480),
      ]).toJson())) as Map<String, dynamic>;
      (damaged['routePoints'] as List)[0] = {'lat': 'north', 'lng': 28.0};

      final restored = RunDraft.fromJson(damaged)!;
      expect(restored.routePoints, hasLength(1));
      expect(restored.routePoints.single.longitude, closeTo(28.0480, 1e-9));
    });

    // Publishing something the runner did not ask to publish is worse than
    // failing to publish something they did.
    test('treats a missing share flag as private', () {
      final damaged = _draft().toJson()..remove('shareToFeed');
      expect(RunDraft.fromJson(damaged)!.shareToFeed, isFalse);
    });
  });

  group('toRunLogDraft', () {
    test('hands the save path exactly what the run screen would have', () {
      final draft = _draft(
        route: const [RoutePoint(latitude: -26.2, longitude: 28.0)],
        startedAt: DateTime.utc(2026, 8, 31, 8, 40),
        heartRate: const HeartRateSummary(
          averageBpm: 148,
          maxBpm: 171,
          coverage: Duration(minutes: 26),
        ),
      );

      final log = draft.toRunLogDraft(backgroundImagePath: '/tmp/photo.jpg');

      expect(log.distanceKm, 5.2);
      expect(log.elapsed, const Duration(minutes: 28, seconds: 14));
      expect(log.averagePace, '5:26 /km');
      expect(log.shareToFeed, isTrue);
      expect(log.routePoints, hasLength(1));
      expect(log.startedAt, DateTime.utc(2026, 8, 31, 8, 40));
      expect(log.backgroundImagePath, '/tmp/photo.jpg');
      expect(log.heartRate?.averageBpm, 148);
    });

    // The caller is the one that checked the file is still there, so a draft
    // that names a photo still publishes without one when told to.
    test('publishes without a backdrop when none is passed', () {
      final draft = _draft(photoPath: '/gone/draft-1.jpg');
      expect(draft.toRunLogDraft().backgroundImagePath, isNull);
    });

    test('carries a private run through as private', () {
      expect(_draft(shareToFeed: false).toRunLogDraft().shareToFeed, isFalse);
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
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
  RunDraftSource source = RunDraftSource.recorded,
  String? externalId,
  ActivityKind activityKind = ActivityKind.run,
  int? elevationGainMeters,
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
    source: source,
    externalId: externalId,
    activityKind: activityKind,
    elevationGainMeters: elevationGainMeters,
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

  // `source` and `externalId` were added without moving the schema version, so
  // that an offline draft already on a phone stays readable. These pin both
  // halves of that bargain down: an old file still reads here, and a new file
  // still reads everything an older build would have looked for.
  group('the imported-run fields', () {
    test('a recorded draft writes neither of them', () {
      final json = _draft().toJson();

      expect(json.containsKey('source'), isFalse);
      expect(json.containsKey('externalId'), isFalse);
    });

    test('a file written before they existed reads as recorded', () {
      final json = _draft().toJson()
        ..remove('source')
        ..remove('externalId');

      final read = RunDraft.fromJson(jsonDecode(jsonEncode(json)));
      expect(read!.source, RunDraftSource.recorded);
      expect(read.externalId, isNull);
      expect(read.isImported, isFalse);
    });

    test('an imported draft survives the round trip', () {
      final read = _roundTrip(
        _draft(
          source: RunDraftSource.healthConnect,
          externalId: 'hc-uuid-1',
          shareToFeed: false,
        ),
      );

      expect(read!.source, RunDraftSource.healthConnect);
      expect(read.externalId, 'hc-uuid-1');
      expect(read.isImported, isTrue);
      expect(read.shareToFeed, isFalse);
    });

    test('a source this build does not know reads as recorded', () {
      // The version gate already rejects a future schema. A label it has never
      // seen is not worth losing a run over on top of that.
      final json = _draft().toJson()..['source'] = 'garmin_direct';

      final read = RunDraft.fromJson(json);
      expect(read!.source, RunDraftSource.recorded);
    });

    test('copyWith keeps them, and can flip sharing on', () {
      final draft = _draft(
        source: RunDraftSource.healthConnect,
        externalId: 'hc-uuid-1',
        shareToFeed: false,
      );

      final shared = draft.copyWith(shareToFeed: true);
      expect(shared.shareToFeed, isTrue);
      expect(shared.source, RunDraftSource.healthConnect);
      expect(shared.externalId, 'hc-uuid-1');

      // And an untouched copy does not silently publish anything.
      expect(draft.copyWith(photoUnavailable: true).shareToFeed, isFalse);
    });
  });

  // Hikes and rides were added to this file the same way `source` and
  // `externalId` were: optional, defaulted to what a file written before them
  // meant, and omitted from the JSON when they hold that default. The schema
  // version deliberately did NOT move, because fromJson rejects any version it
  // does not recognise — bumping it would have made every offline draft
  // already sitting on a phone unreadable, losing real unsent runs to announce
  // a field.
  group('activity kind', () {
    test("a run's file does not carry the key at all", () {
      final json = _draft().toJson();

      expect(json.containsKey('activityKind'), isFalse);
      // Which is what lets an older build read this file unchanged.
      expect(RunDraft.fromJson(json)!.activityKind, ActivityKind.run);
    });

    test('a hike and a ride round-trip', () {
      for (final kind in [ActivityKind.hike, ActivityKind.ride]) {
        final restored = _roundTrip(_draft(activityKind: kind))!;
        expect(restored.activityKind, kind, reason: kind.name);
      }
    });

    test('a kind an older build has never heard of reads as a run', () {
      final json = _draft(activityKind: ActivityKind.ride).toJson()
        ..['activityKind'] = 'kayak';

      // Degraded, not discarded. The draft is somebody's only copy of an
      // outing; publishing it as a run beats dropping it on the floor.
      final restored = RunDraft.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.activityKind, ActivityKind.run);
      expect(restored.distanceKm, 5.2);
    });

    test('copyWith carries the kind', () {
      // copyWith rebuilds field by field and silently drops anything left out,
      // so a hike would quietly become a run the moment its photo changed.
      final hike = _draft(activityKind: ActivityKind.hike);

      expect(hike.copyWith(photoPath: 'a.jpg').activityKind, ActivityKind.hike);
      expect(hike.copyWith(shareToFeed: false).activityKind, ActivityKind.hike);
    });

    test('the save path is handed the kind', () {
      final ride = _draft(activityKind: ActivityKind.ride);

      expect(ride.toRunLogDraft().activityKind, ActivityKind.ride);
    });
  });

  group('elevation gain', () {
    test('is omitted when nothing measured it', () {
      // Null and zero are different answers, and a manually entered session
      // must not be recorded as a flat one.
      expect(_draft().toJson().containsKey('elevationGainMeters'), isFalse);
      expect(_roundTrip(_draft())!.elevationGainMeters, isNull);
    });

    test('round-trips, including a measured zero', () {
      expect(_roundTrip(_draft(elevationGainMeters: 412))!.elevationGainMeters,
          412);
      expect(
          _roundTrip(_draft(elevationGainMeters: 0))!.elevationGainMeters, 0);
    });

    test('survives copyWith and reaches the save path', () {
      final hike = _draft(activityKind: ActivityKind.hike,
          elevationGainMeters: 250);

      expect(hike.copyWith(photoPath: 'a.jpg').elevationGainMeters, 250);
      expect(hike.toRunLogDraft().elevationGainMeters, 250);
    });
  });
}

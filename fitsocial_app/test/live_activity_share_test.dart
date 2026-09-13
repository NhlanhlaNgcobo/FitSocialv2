import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/domain/activity_kind.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/tracking/domain/live_activity_share.dart';

void main() {
  group('LiveShareSnapshot', () {
    LiveShareSnapshot snapshot({
      double distanceKm = 1.0,
      bool isPaused = false,
      int points = 3,
      String pace = '5:30',
    }) =>
        LiveShareSnapshot(
          distanceKm: distanceKm,
          elapsed: const Duration(minutes: 5),
          paceLabel: pace,
          isPaused: isPaused,
          route: [
            for (var i = 0; i < points; i++)
              RoutePoint(latitude: i * 0.001, longitude: 0),
          ],
        );

    test('the clock alone is not a reason to write', () {
      // Elapsed differs; nothing else does. The viewer runs its own clock.
      final a = snapshot();
      final b = LiveShareSnapshot(
        distanceKm: a.distanceKm,
        elapsed: a.elapsed + const Duration(seconds: 30),
        paceLabel: a.paceLabel,
        isPaused: a.isPaused,
        route: a.route,
      );

      expect(b.differsFrom(a), isFalse);
    });

    test('distance, a pause, a new fix or a new pace each earn a write', () {
      final base = snapshot();

      expect(snapshot(distanceKm: 1.2).differsFrom(base), isTrue);
      expect(snapshot(isPaused: true).differsFrom(base), isTrue);
      expect(snapshot(points: 4).differsFrom(base), isTrue);
      expect(snapshot(pace: '5:31').differsFrom(base), isTrue);
      expect(snapshot().differsFrom(null), isTrue);
    });

    test('the update carries the newest fix as the position', () {
      final update = snapshot(points: 3).toUpdate();

      expect(update['lat'], closeTo(0.002, 1e-9));
      expect(update['lng'], 0);
      expect(update['trail'], hasLength(3));
      expect(update['elapsedSeconds'], 300);
    });

    test('no fix yet means no position, not a position at zero', () {
      // Null Island is a real place and somebody would be drawn there.
      final update = snapshot(points: 0).toUpdate();

      expect(update.containsKey('lat'), isFalse);
      expect(update.containsKey('lng'), isFalse);
      expect(update['trail'], isEmpty);
    });
  });

  group('LiveActivityShare.thinTrail', () {
    test('a short trail is written whole', () {
      final route = [
        for (var i = 0; i < 10; i++) RoutePoint(latitude: i.toDouble(), longitude: 0),
      ];

      expect(LiveActivityShare.thinTrail(route), hasLength(10));
    });

    test('a long trail is thinned but keeps both ends', () {
      final route = [
        for (var i = 0; i < 5000; i++)
          RoutePoint(latitude: i.toDouble(), longitude: 0),
      ];

      final trail = LiveActivityShare.thinTrail(route);

      expect(trail.length, lessThanOrEqualTo(LiveActivityShare.maxTrailPoints + 1));
      expect(trail.first.latitude, 0);
      expect(trail.last.latitude, 4999);
    });
  });

  group('LiveActivityShare.fromMap', () {
    final startedAt = DateTime(2026, 9, 12, 6, 30);

    Map<String, dynamic> doc({
      String status = 'live',
      DateTime? updatedAt,
      DateTime? expiresAt,
    }) =>
        {
          'authorId': 'u1',
          'authorName': 'Bear',
          'activityType': 'ride',
          'status': status,
          'startedAt': startedAt,
          'updatedAt': updatedAt ?? DateTime.now(),
          if (expiresAt != null) 'expiresAt': expiresAt,
          'lat': -26.2,
          'lng': 28.0,
          'distanceKm': 12.345,
          'elapsedSeconds': 1800,
          'paceLabel': '24.7',
          'isPaused': false,
          'trail': [
            {'lat': -26.1, 'lng': 28.0},
            {'lat': -26.2, 'lng': 28.0},
          ],
        };

    test('reads a well-formed document', () {
      final share = LiveActivityShare.fromMap('s1', doc())!;

      expect(share.id, 's1');
      expect(share.kind, ActivityKind.ride);
      expect(share.isLive, isTrue);
      expect(share.position?.latitude, -26.2);
      expect(share.distanceKm, 12.345);
      expect(share.elapsed, const Duration(minutes: 30));
      expect(share.trail, hasLength(2));
      expect(share.hasLostContact, isFalse);
      expect(share.isExpired, isFalse);
    });

    test('a missing expiry falls back to the lifetime from the start', () {
      final share = LiveActivityShare.fromMap('s1', doc())!;

      expect(share.expiresAt, startedAt.add(LiveActivityShare.lifetime));
    });

    test('a live document that has gone quiet reads as lost contact', () {
      final share = LiveActivityShare.fromMap(
        's1',
        doc(updatedAt: DateTime.now().subtract(const Duration(minutes: 10))),
      )!;

      expect(share.isLive, isTrue);
      expect(share.hasLostContact, isTrue);
    });

    test('a finished document is never lost contact, however old', () {
      final share = LiveActivityShare.fromMap(
        's1',
        doc(
          status: 'ended',
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      )!;

      expect(share.isLive, isFalse);
      expect(share.hasLostContact, isFalse);
    });

    test('a status this build has not heard of is treated as ended', () {
      final share = LiveActivityShare.fromMap('s1', doc(status: 'paused'))!;

      expect(share.phase, LiveSharePhase.ended);
    });

    test('a document with no author or no start is not a share', () {
      expect(
        LiveActivityShare.fromMap('s1', doc()..remove('authorId')),
        isNull,
      );
      expect(
        LiveActivityShare.fromMap('s1', doc()..remove('startedAt')),
        isNull,
      );
    });
  });
}

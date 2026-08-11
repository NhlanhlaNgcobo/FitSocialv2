import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/main/data/activity_session_parsing.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';

void main() {
  ActivitySession session({
    required String id,
    required ActivityKind kind,
    required DateTime startedAt,
    int minutes = 45,
    bool sharedToFeed = false,
    String? postId,
  }) {
    return ActivitySession(
      id: id,
      kind: kind,
      title: 'Session',
      startedAt: startedAt,
      duration: Duration(minutes: minutes),
      calories: 0,
      sharedToFeed: sharedToFeed,
      postId: postId,
    );
  }

  group('duration labels', () {
    test('reads the minutes a workout post stored', () {
      expect(minutesFromDurationLabel('45 min'), 45);
      expect(minutesFromDurationLabel('120 min'), 120);
    });

    test('is zero for anything it cannot read', () {
      expect(minutesFromDurationLabel(null), 0);
      expect(minutesFromDurationLabel(''), 0);
      expect(minutesFromDurationLabel('a while'), 0);
    });
  });

  group('calorie labels', () {
    test('reads what was stored', () {
      expect(kcalFromLabel('320 kcal'), 320);
    });

    test('reads the placeholder every old workout carried as nothing', () {
      expect(kcalFromLabel('0 kcal'), 0);
      expect(kcalFromLabel(null), 0);
    });
  });

  group('distance metrics', () {
    test('finds the km figure wherever it sits in the strip', () {
      expect(distanceFromMetricLabels(['5.02 km', '28:14', '5:37 /km']), 5.02);
      expect(distanceFromMetricLabels(['28:14', '12 km']), 12);
    });

    test('is null when the strip holds no distance', () {
      expect(distanceFromMetricLabels(['45 min', '0 kcal', '3 moves']), isNull);
      expect(distanceFromMetricLabels(const []), isNull);
    });

    test('is not fooled by the pace metric, which also says km', () {
      // "5:37 /km" is a pace, not a distance, and must not parse as one.
      expect(distanceFromMetricLabels(['5:37 /km']), isNull);
    });
  });

  group('elapsed-time metrics', () {
    test('reads mm:ss and h:mm:ss', () {
      expect(
        durationFromMetricLabels(['5.02 km', '28:14', '5:37 /km']),
        const Duration(minutes: 28, seconds: 14),
      );
      expect(
        durationFromMetricLabels(['21.10 km', '1:52:07', '5:18 /km']),
        const Duration(hours: 1, minutes: 52, seconds: 7),
      );
    });

    test('does not mistake the pace for the elapsed time', () {
      // Pace carries a "/km" suffix, so the anchored pattern rejects it and
      // the real elapsed time is found instead.
      final elapsed = durationFromMetricLabels(['5:37 /km', '28:14']);
      expect(elapsed, const Duration(minutes: 28, seconds: 14));
    });

    test('is null when the strip holds no clock at all', () {
      expect(durationFromMetricLabels(['45 min', '0 kcal']), isNull);
    });
  });

  group('mergeSessions', () {
    final monday = DateTime(2026, 8, 3, 18);

    test('keeps a post-only session, which is the whole point', () {
      final merged = mergeSessions(
        logged: const [],
        fromPosts: [
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday,
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.postId, 'p1');
    });

    test('drops the post a log already points at', () {
      final merged = mergeSessions(
        logged: [
          session(
            id: 'log1',
            kind: ActivityKind.workout,
            startedAt: monday,
            sharedToFeed: true,
            postId: 'p1',
          ),
        ],
        fromPosts: [
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday.add(const Duration(seconds: 4)),
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'log1');
    });

    test('drops the post matching a shared log that has no id to match on', () {
      final merged = mergeSessions(
        logged: [
          // Written in the window before postId was recorded.
          session(
            id: 'log1',
            kind: ActivityKind.workout,
            startedAt: monday,
            minutes: 62,
            sharedToFeed: true,
          ),
        ],
        fromPosts: [
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday.add(const Duration(seconds: 6)),
            minutes: 62,
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 'log1');
    });

    test('keeps a genuinely different session on the same day', () {
      final merged = mergeSessions(
        logged: [
          session(
            id: 'log1',
            kind: ActivityKind.workout,
            startedAt: monday,
            minutes: 62,
            sharedToFeed: true,
          ),
        ],
        fromPosts: [
          // Same day, same kind, but a different length — a second session.
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday.add(const Duration(hours: 3)),
            minutes: 30,
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(2));
    });

    test('a run and a workout of the same length never collapse', () {
      final merged = mergeSessions(
        logged: [
          session(
            id: 'log1',
            kind: ActivityKind.run,
            startedAt: monday,
            minutes: 45,
            sharedToFeed: true,
          ),
        ],
        fromPosts: [
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday,
            minutes: 45,
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(2));
    });

    test('an unshared log never absorbs a post', () {
      final merged = mergeSessions(
        logged: [
          // Kept private, so no post of its own can exist — a matching post is
          // somebody else's session, not this one's twin.
          session(
            id: 'log1',
            kind: ActivityKind.workout,
            startedAt: monday,
            minutes: 45,
          ),
        ],
        fromPosts: [
          session(
            id: 'p1',
            kind: ActivityKind.workout,
            startedAt: monday,
            minutes: 45,
            postId: 'p1',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged, hasLength(2));
    });

    test('returns everything newest first', () {
      final merged = mergeSessions(
        logged: [
          session(id: 'a', kind: ActivityKind.run, startedAt: monday),
        ],
        fromPosts: [
          session(
            id: 'b',
            kind: ActivityKind.workout,
            startedAt: monday.add(const Duration(days: 2)),
            postId: 'b',
            sharedToFeed: true,
          ),
          session(
            id: 'c',
            kind: ActivityKind.workout,
            startedAt: monday.subtract(const Duration(days: 5)),
            postId: 'c',
            sharedToFeed: true,
          ),
        ],
      );

      expect(merged.map((s) => s.id), ['b', 'a', 'c']);
    });
  });
}

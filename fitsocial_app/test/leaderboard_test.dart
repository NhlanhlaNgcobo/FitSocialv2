import 'package:fitsocial_app/features/leaderboards/application/leaderboard_providers.dart';
import 'package:fitsocial_app/features/leaderboards/domain/leaderboard.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry _entry(
  String userId, {
  int steps = 0,
  int activeMinutes = 0,
  int sessions = 0,
  int streak = 0,
  int activeDays = 0,
}) =>
    LeaderboardEntry(
      userId: userId,
      steps: steps,
      activeMinutes: activeMinutes,
      sessions: sessions,
      streak: streak,
      activeDays: activeDays,
    );

void main() {
  group('entries', () {
    test('an entry reads the four figures and the day count', () {
      final entry = LeaderboardEntry.fromMap('u1', const {
        'userId': 'u1',
        'periodId': '2026-W40',
        'scope': 'week',
        'steps': 52000,
        'activeMinutes': 320,
        'sessions': 5,
        'streak': 4,
        'activeDays': 4,
      });
      expect(entry.steps, 52000);
      expect(entry.valueOf(LeaderboardMetric.activeMinutes), 320);
      expect(entry.valueOf(LeaderboardMetric.sessions), 5);
      expect(entry.valueOf(LeaderboardMetric.streak), 4);
      expect(entry.activeDays, 4);
    });

    test('an entry from an older build reads as zeros, not as an error', () {
      final entry = LeaderboardEntry.fromMap('u1', const {'steps': 'lots'});
      expect(entry.steps, 0);
      expect(entry.activeMinutes, 0);
      expect(entry.activeDays, 0);
    });
  });

  group('building a board', () {
    test('orders on the chosen figure, best first', () {
      final board = buildBoard(
        entries: [
          _entry('a', steps: 30000),
          _entry('b', steps: 52000),
          _entry('c', steps: 41000),
        ],
        metric: LeaderboardMetric.steps,
        viewerId: 'a',
      );
      expect(board.rows.map((r) => r.userId), ['b', 'c', 'a']);
      expect(board.rows.map((r) => r.rank), [1, 2, 3]);
      expect(board.rows.map((r) => r.value), [52000, 41000, 30000]);
    });

    test('switching figure reorders the same people', () {
      final entries = [
        _entry('walker', steps: 90000, sessions: 1),
        _entry('lifter', steps: 20000, sessions: 6),
      ];
      expect(
        buildBoard(
          entries: entries,
          metric: LeaderboardMetric.steps,
          viewerId: null,
        ).rows.first.userId,
        'walker',
      );
      expect(
        buildBoard(
          entries: entries,
          metric: LeaderboardMetric.sessions,
          viewerId: null,
        ).rows.first.userId,
        'lifter',
      );
    });

    test('nobody appears on a board they have no figure for', () {
      // Three sessions and no step sync: on the sessions board, absent from the
      // steps board rather than sitting at the bottom of it on zero.
      final entries = [_entry('a', steps: 30000), _entry('b', sessions: 3)];
      final steps = buildBoard(
        entries: entries,
        metric: LeaderboardMetric.steps,
        viewerId: null,
      );
      expect(steps.rows.map((r) => r.userId), ['a']);
      final sessions = buildBoard(
        entries: entries,
        metric: LeaderboardMetric.sessions,
        viewerId: null,
      );
      expect(sessions.rows.map((r) => r.userId), ['b']);
    });

    test('equal figures share a rank, and the next place skips', () {
      final board = buildBoard(
        entries: [
          _entry('a', steps: 40000, activeDays: 5),
          _entry('b', steps: 40000, activeDays: 5),
          _entry('c', steps: 10000),
        ],
        metric: LeaderboardMetric.steps,
        viewerId: null,
      );
      expect(board.rows.map((r) => r.rank), [1, 1, 3]);
    });

    test('a tie is broken by active days, then by id, and never moves', () {
      List<String> order() => buildBoard(
            entries: [
              _entry('zed', steps: 40000, activeDays: 3),
              _entry('amy', steps: 40000, activeDays: 3),
              _entry('bob', steps: 40000, activeDays: 6),
            ],
            metric: LeaderboardMetric.steps,
            viewerId: null,
          ).rows.map((r) => r.userId).toList();

      // Steadiest of the three first, then the two threes by id.
      expect(order(), ['bob', 'amy', 'zed']);
      // Same input, same answer: a board must not reshuffle between refreshes.
      expect(order(), order());
    });

    test('the board is capped, and the viewer is kept at their real rank', () {
      final board = buildBoard(
        entries: [
          for (var i = 0; i < 12; i++) _entry('u$i', steps: 50000 - i * 100),
          _entry('me', steps: 100),
        ],
        metric: LeaderboardMetric.steps,
        viewerId: 'me',
        limit: 3,
      );
      expect(board.rows.length, 3);
      expect(board.rows.map((r) => r.userId), ['u0', 'u1', 'u2']);
      expect(board.viewerRow, isNotNull);
      expect(board.viewerRow!.userId, 'me');
      expect(
        board.viewerRow!.rank,
        13,
        reason: 'their real place, not the cap',
      );
      expect(board.viewerRow!.isViewer, isTrue);
    });

    test('a viewer already in the top is not pinned under it twice', () {
      final board = buildBoard(
        entries: [_entry('me', steps: 50000), _entry('a', steps: 10000)],
        metric: LeaderboardMetric.steps,
        viewerId: 'me',
        limit: 3,
      );
      expect(board.viewerRow, isNull);
      expect(board.rows.first.isViewer, isTrue);
    });

    test('a viewer with nothing on this board is not pinned under it', () {
      final board = buildBoard(
        entries: [_entry('a', steps: 10000), _entry('me', sessions: 2)],
        metric: LeaderboardMetric.steps,
        viewerId: 'me',
        limit: 3,
      );
      expect(board.viewerRow, isNull);
      expect(board.rows.map((r) => r.userId), ['a']);
    });

    test('no entries is an empty board, not a crash', () {
      final board = buildBoard(
        entries: const [],
        metric: LeaderboardMetric.steps,
        viewerId: 'me',
      );
      expect(board.isEmpty, isTrue);
      expect(board.viewerRow, isNull);
    });
  });

  group('which period a board is', () {
    test('a week board asks for the ISO week, a month board for the month', () {
      final wednesday = DateTime(2026, 9, 30);
      expect(
        periodIdFor(LeaderboardScope.week, today: wednesday),
        '2026-W40',
      );
      expect(periodIdFor(LeaderboardScope.month, today: wednesday), '2026-09');
    });

    test('a year-end week belongs to the ISO year of its Thursday', () {
      expect(
        periodIdFor(LeaderboardScope.week, today: DateTime(2027, 1, 1)),
        '2026-W53',
      );
    });
  });
}

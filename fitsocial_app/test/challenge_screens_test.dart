import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsocial_app/features/challenges/application/challenge_providers.dart';
import 'package:fitsocial_app/features/challenges/data/challenge_repository.dart';
import 'package:fitsocial_app/features/challenges/data/challenge_repository_contract.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_badges.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_clock.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_copy.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_models.dart';
import 'package:fitsocial_app/features/challenges/domain/challenge_task.dart';
import 'package:fitsocial_app/features/challenges/domain/daily_health.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_outcome_screen.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_status_strip.dart';
import 'package:fitsocial_app/features/challenges/presentation/challenge_tracker_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';

/// Africa/Johannesburg, pinned so a day key never depends on where the test
/// machine happens to be.
const _clock = ChallengeClock(utcOffsetMinutes: 120);

/// A run under way, wired to whatever the fake repository is holding.
ChallengeEnrollment _enrollment({
  EnrollmentStatus status = EnrollmentStatus.active,
  int daysCompleted = 12,
  int currentStreak = 5,
  int longestStreak = 9,
  int consecutiveMissedDays = 0,
  int pointsEarned = 1240,
}) {
  return ChallengeEnrollment(
    id: 'me_pulse75_2026-08-01',
    userId: 'me',
    challengeKey: ChallengeKey.pulse75,
    startDayKey: '2026-08-01',
    utcOffsetMinutes: 120,
    pointsEarned: pointsEarned,
    progress: EnrollmentProgress(
      daysCompleted: daysCompleted,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      consecutiveMissedDays: consecutiveMissedDays,
      status: status,
    ),
  );
}

/// Everything the screens read, held in memory.
///
/// Written by hand rather than generated: the surface is small, and a fake that
/// records its writes is what lets the manual-task test assert that a tap
/// reached the repository at all.
class _FakeChallengeRepository implements ChallengeRepository {
  _FakeChallengeRepository({required this.enrollment, required this.day});

  ChallengeEnrollment enrollment;
  DailyProgress day;

  /// Nothing awarded by default. The screens under test read the shelf but do
  /// not assert on it; the badge surfaces are covered by the domain tests.
  List<UserBadge> badges = const [];

  /// (task, value) for every manual write the UI made.
  final List<(ChallengeTask, int)> manualWrites = [];
  int clockRefreshes = 0;

  @override
  Stream<List<ChallengeEnrollment>> watchEnrollments(String userId) =>
      Stream.value([enrollment]);

  @override
  Stream<ChallengeEnrollment?> watchEnrollment(String enrollmentId) =>
      Stream.value(enrollment);

  @override
  Stream<DailyProgress> watchDay(String enrollmentId, String dayKey) =>
      Stream.value(day);

  @override
  Stream<List<DailyProgress>> watchRecentDays(String enrollmentId, int days) =>
      Stream.value([day]);

  @override
  Future<ChallengeEnrollment> enroll({
    required String userId,
    required ChallengeKey challengeKey,
    required int utcOffsetMinutes,
  }) async =>
      enrollment;

  @override
  Future<void> abandon(String enrollmentId) async {}

  @override
  Future<void> setManualTask({
    required String enrollmentId,
    required String dayKey,
    required ChallengeTask task,
    required int value,
  }) async {
    manualWrites.add((task, value));
  }

  @override
  Future<void> syncUserClock(String userId, int utcOffsetMinutes) async {}

  @override
  Future<void> refreshClock(String enrollmentId, int utcOffsetMinutes) async {
    clockRefreshes += 1;
  }

  @override
  Future<void> recordDailyHealth({
    required String userId,
    required String dayKey,
    required DailyHealthReading reading,
    required String source,
  }) async {}

  @override
  Stream<EarlyWormStreak> watchEarlyWorm(String userId) =>
      Stream.value(const EarlyWormStreak());

  @override
  Stream<List<UserBadge>> watchBadges(String userId) => Stream.value(badges);

  @override
  Stream<int> watchPoints(String userId) => Stream.value(0);

  @override
  Stream<ChallengeStats> watchStats(ChallengeKey challengeKey) =>
      Stream.value(const ChallengeStats());
}

Widget _host(Widget child, _FakeChallengeRepository repository) {
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      challengeRepositoryProvider.overrideWithValue(repository),
      challengeClockProvider.overrideWithValue(_clock),
    ],
    child: MaterialApp(home: child),
  );
}

/// A day with every task met except the two the user counts by hand.
DailyProgress _partialDay() {
  return DailyProgress(
    dayKey: _clock.today(),
    values: {
      for (final task in ChallengeTask.values)
        if (!task.isManual) task: task.target,
      ChallengeTask.water: 6,
      ChallengeTask.reading: 4,
    },
  );
}

/// The tracker is a ListView, so anything past the fold is never built and a
/// finder for it fails for a reason that has nothing to do with the code. A
/// tall surface puts all seven rows on screen at once.
Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// The tracker on a real budget phone rather than on a tablet.
///
/// [_useTallSurface] above is 800 wide, which is what let the stat strip
/// overflow ship: at that width every label fits with room to spare. The
/// tester who reported the jumbled streak row was on a 720x1600 handset --
/// 360 logical pixels across -- so that is the width worth defending. Still
/// tall, because the tracker is a ListView and rows past the fold never build.
Future<void> _useHandsetSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Re-runs [child] at a system font size other than the default.
///
/// Reads the ambient data and copies it rather than building a fresh
/// [MediaQueryData], which would drop the surface size the test just set.
Widget _atTextScale(double scale, Widget child) {
  return Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child,
    ),
  );
}

void main() {
  group('tracker screen', () {
    testWidgets('lists all seven tasks with their figures', (tester) async {
      await _useTallSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      for (final task in ChallengeTask.values) {
        expect(find.text(task.label), findsOneWidget,
            reason: '${task.key} row missing');
      }

      // Five of seven: the two manual ones are short.
      expect(find.text('5 / 7'), findsOneWidget);
      expect(find.text('6 / 8 glasses'), findsOneWidget);
      expect(find.text('4 / 10 pages'), findsOneWidget);
      expect(find.text('12'), findsOneWidget); // days completed, in the ring
    });

    testWidgets('a manual task can be moved, an automatic one cannot',
        (tester) async {
      await _useTallSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      // Two manual rows, each with a plus and a minus, and nothing else on the
      // screen offering to move a number. This is the anti-gaming rule as the
      // user meets it: there is no control to fake 12,000 steps with.
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.remove_rounded), findsNWidgets(2));
      expect(
        find.byIcon(Icons.lock_outline_rounded),
        findsNWidgets(5),
        reason: 'the five automatic tasks are read-only',
      );

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      expect(repository.manualWrites, hasLength(1));
      expect(repository.manualWrites.single.$1, ChallengeTask.water);
      expect(repository.manualWrites.single.$2, 7);
    });

    testWidgets('opening the tracker re-stamps the run clock', (tester) async {
      await _useTallSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(repository.clockRefreshes, 1);
    });

    testWidgets('two missed days puts the warning band up', (tester) async {
      await _useTallSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(
          status: EnrollmentStatus.danger,
          currentStreak: 0,
          consecutiveMissedDays: 2,
        ),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('TWO DAYS MISSED'), findsOneWidget);
      expect(
        find.text('Complete tomorrow or you are eliminated from Pulse 75.'),
        findsOneWidget,
      );
    });

    testWidgets('an eliminated run offers no way to quit it again',
        (tester) async {
      await _useTallSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(status: EnrollmentStatus.eliminated),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('ELIMINATED'), findsOneWidget);
      expect(find.text('QUIT PULSE 75'), findsNothing);
    });
  });

  /// The strip reading "0 DAY STREAK / 0 BEST STREAK / 0 POINTS THIS
  /// CHALLENGE". On the reporter's phone the three labels ran into each other
  /// and the last one walked off the right edge -- a plain RenderFlex
  /// overflow, invisible in these tests because they all ran 800 wide.
  ///
  /// Asserted through [WidgetTester.takeException] rather than by measuring
  /// anything: an overflowing Row reports a FlutterError while it paints, and
  /// that error is the bug itself.
  group('tracker stat strip', () {
    testWidgets('fits a 360-wide handset', (tester) async {
      await _useHandsetSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(ChallengeCopy.bestStreak), findsOneWidget);
      expect(find.text(ChallengeCopy.pointsThisChallenge), findsOneWidget);
    });

    testWidgets('fits a 360-wide handset with large system text',
        (tester) async {
      await _useHandsetSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        _atTextScale(
          1.3,
          const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        ),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a four-figure point total still fits', (tester) async {
      await _useHandsetSurface(tester);
      final repository = _FakeChallengeRepository(
        // Day 75 of a clean run: the widest every figure ever gets.
        enrollment: _enrollment(
          daysCompleted: 75,
          currentStreak: 75,
          longestStreak: 75,
          pointsEarned: 99999,
        ),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeTrackerScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    /// The outcome screen sets four stats in one row. It overflowed on a
    /// handset at the default font size, which made the reward for finishing
    /// seventy-five days the most broken screen in the feature.
    testWidgets('the finish screen fits a handset too', (tester) async {
      await _useHandsetSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(
          status: EnrollmentStatus.completed,
          daysCompleted: 75,
          longestStreak: 75,
          pointsEarned: 99999,
        ),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const ChallengeOutcomeScreen(enrollmentId: 'me_pulse75_2026-08-01'),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BEST STREAK'), findsOneWidget);
      expect(find.text('POINTS'), findsOneWidget);
    });

    /// The strip on the home feed. This one only broke at a raised system font
    /// size, which is why it is worth a case of its own.
    testWidgets('the home strip fits at a large system font size',
        (tester) async {
      await _useHandsetSurface(tester);
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        _atTextScale(1.3, const Scaffold(body: ChallengeStatusStrip())),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('home status strip', () {
    testWidgets('names only what is still outstanding', (tester) async {
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const Scaffold(body: ChallengeStatusStrip()),
        repository,
      ));
      await tester.pumpAndSettle();

      // The two short tasks, with what is left of each.
      expect(find.text('Water 2 glasses'), findsOneWidget);
      expect(find.text('Reading 6 pages'), findsOneWidget);

      // Nothing about the five already done. A reminder to log a workout you
      // finished four hours ago is how a nudge becomes an annoyance.
      expect(find.text('Workout 0 min'), findsNothing);
      expect(find.textContaining('Steps'), findsNothing);
    });

    testWidgets('says so when the day is done', (tester) async {
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(),
        day: DailyProgress(
          dayKey: _clock.today(),
          values: {for (final task in ChallengeTask.values) task: task.target},
        ),
      );

      await tester.pumpWidget(_host(
        const Scaffold(body: ChallengeStatusStrip()),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('All seven done. Streak is safe.'), findsOneWidget);
      expect(find.text('7 / 7'), findsOneWidget);
    });

    testWidgets('recruits when nothing is running', (tester) async {
      final repository = _FakeChallengeRepository(
        enrollment: _enrollment(status: EnrollmentStatus.abandoned),
        day: _partialDay(),
      );

      await tester.pumpWidget(_host(
        const Scaffold(body: ChallengeStatusStrip()),
        repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('NO CHALLENGE RUNNING.'), findsOneWidget);
      expect(find.text('Seven tasks. Every day. 75 days.'), findsOneWidget);
    });
  });
}

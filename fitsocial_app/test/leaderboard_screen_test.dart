import 'package:fitsocial_app/core/config/feature_flags.dart';
import 'package:fitsocial_app/features/leaderboards/application/leaderboard_providers.dart';
import 'package:fitsocial_app/features/leaderboards/data/leaderboard_repository.dart';
import 'package:fitsocial_app/features/leaderboards/domain/leaderboard.dart';
import 'package:fitsocial_app/features/leaderboards/presentation/leaderboard_card.dart';
import 'package:fitsocial_app/features/leaderboards/presentation/leaderboard_screen.dart';
import 'package:fitsocial_app/features/main/application/content_providers.dart';
import 'package:fitsocial_app/features/main/domain/app_models.dart';
import 'package:fitsocial_app/features/main/domain/progress_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLeaderboardRepository implements LeaderboardRepository {
  _FakeLeaderboardRepository({
    this.entries = const [],
    this.optedOut = false,
  });

  List<LeaderboardEntry> entries;
  bool optedOut;

  /// Every period a board asked for, and every opt-out written.
  final askedFor = <String>[];
  final written = <bool>[];

  @override
  Future<List<LeaderboardEntry>> fetchEntries({
    required List<String> userIds,
    required String periodId,
  }) async {
    askedFor.add(periodId);
    return entries
        .where((entry) => userIds.contains(entry.userId))
        .toList(growable: false);
  }

  @override
  Stream<bool> watchOptOut(String userId) => Stream.value(optedOut);

  @override
  Future<void> setOptOut(String userId, bool value) async {
    written.add(value);
    optedOut = value;
  }
}

UserSearchResult _profile(String id, String name) => UserSearchResult(
      id: id,
      displayName: name,
      handle: '@$id',
      initials: name.substring(0, 1),
      postsCount: 0,
    );

Widget _host(
  _FakeLeaderboardRepository repository, {
  bool enabled = true,
  Set<String> following = const {'u1', 'u2'},
  Widget? child,
}) {
  final flags =
      FeatureFlags.defaults.withFlag(FeatureFlag.leaderboards, enabled);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      followingIdsProvider.overrideWith((ref) => Stream.value(following)),
      leaderboardRepositoryProvider.overrideWithValue(repository),
      featureFlagsProvider.overrideWith((ref) => Stream.value(flags)),
      userProfileProvider('me')
          .overrideWith((ref) async => _profile('me', 'Me')),
      userProfileProvider('u1')
          .overrideWith((ref) async => _profile('u1', 'Amy')),
      userProfileProvider('u2')
          .overrideWith((ref) async => _profile('u2', 'Bob')),
    ],
    child: MaterialApp(home: child ?? const LeaderboardScreen()),
  );
}

/// The current week, which is the only window the card draws on.
final _thisWeek = ProgressWindow.forOffset(ProgressPeriod.week, 0);

void main() {
  group('the board', () {
    testWidgets('ranks the people you follow and marks your own row',
        (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [
          LeaderboardEntry(userId: 'u1', steps: 52000, activeDays: 5),
          LeaderboardEntry(userId: 'me', steps: 41000, activeDays: 4),
          LeaderboardEntry(userId: 'u2', steps: 12000, activeDays: 2),
        ],
      );
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(find.text('Amy'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      // The viewer is named "You" rather than by their own display name.
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Me'), findsNothing);

      expect(find.text('52,000'), findsOneWidget);
      expect(find.text('41,000'), findsOneWidget);
      expect(find.text('5 active days'), findsOneWidget);
      expect(find.text('2 active days'), findsOneWidget);
    });

    testWidgets('a different figure reorders the same people', (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [
          LeaderboardEntry(userId: 'u1', steps: 52000, sessions: 1),
          LeaderboardEntry(userId: 'u2', steps: 12000, sessions: 6),
        ],
      );
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sessions'));
      await tester.pumpAndSettle();

      // The sessions figure is on screen and the step figures are gone.
      expect(find.text('6'), findsOneWidget);
      expect(find.text('52,000'), findsNothing);
    });

    testWidgets('a month board asks for the month, not the week',
        (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [LeaderboardEntry(userId: 'u1', steps: 10)],
      );
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();
      expect(repository.askedFor.first, periodIdFor(LeaderboardScope.week));

      await tester.tap(find.text('This month'));
      await tester.pumpAndSettle();
      expect(repository.askedFor.last, periodIdFor(LeaderboardScope.month));
    });

    testWidgets('says so plainly when there is nothing on it', (tester) async {
      await tester.pumpWidget(_host(_FakeLeaderboardRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Nothing on this board yet'), findsOneWidget);
    });

    testWidgets('is empty while leaderboards are switched off', (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [LeaderboardEntry(userId: 'u1', steps: 52000)],
      );
      await tester.pumpWidget(_host(repository, enabled: false));
      await tester.pumpAndSettle();

      expect(find.text('Amy'), findsNothing);
      expect(
        repository.askedFor,
        isEmpty,
        reason: 'a board that is off must not even read',
      );
    });
  });

  group('the opt-out', () {
    testWidgets('writes the preference and reads back off the profile',
        (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [LeaderboardEntry(userId: 'u1', steps: 52000)],
      );
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      // The switch reads "show me", so turning it off is what opts out.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(repository.written, [true]);
    });

    testWidgets('an opted-out user is told their figures are gone',
        (tester) async {
      final repository = _FakeLeaderboardRepository(optedOut: true);
      await tester.pumpWidget(_host(repository));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('You are off every board'),
        findsOneWidget,
      );
    });
  });

  group('the Progress card', () {
    testWidgets('previews the top of the board', (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [
          LeaderboardEntry(userId: 'u1', steps: 52000, activeDays: 5),
          LeaderboardEntry(userId: 'u2', steps: 12000, activeDays: 2),
        ],
      );
      await tester.pumpWidget(
        _host(
          repository,
          child: Scaffold(
            body: SingleChildScrollView(
              child: LeaderboardCard(window: _thisWeek),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Steps this week'), findsOneWidget);
      expect(find.text('52,000'), findsOneWidget);
    });

    testWidgets('draws nothing for a window no board covers', (tester) async {
      final repository = _FakeLeaderboardRepository(
        entries: const [LeaderboardEntry(userId: 'u1', steps: 52000)],
      );
      await tester.pumpWidget(
        _host(
          repository,
          child: Scaffold(
            body: SingleChildScrollView(
              // Last week: there is no board to page back to.
              child: LeaderboardCard(
                window: ProgressWindow.forOffset(ProgressPeriod.week, -1),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('52,000'), findsNothing);
      expect(repository.askedFor, isEmpty);
    });

    testWidgets('draws nothing while the board is empty', (tester) async {
      await tester.pumpWidget(
        _host(
          _FakeLeaderboardRepository(),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LeaderboardCard(window: _thisWeek),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Steps this week'), findsNothing);
    });
  });
}

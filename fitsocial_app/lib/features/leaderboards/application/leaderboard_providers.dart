import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../shared/time/period_keys.dart';
import '../../main/application/content_providers.dart'
    show currentUserIdProvider, followingIdsProvider;
import '../data/leaderboard_repository.dart';
import '../domain/leaderboard.dart';

/// Whether the boards are part of the app right now.
final leaderboardsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureEnabledProvider(FeatureFlag.leaderboards)),
);

/// `YYYY-MM-DD` for a local calendar date. The same shape the day keys the
/// stats pipeline writes have, derived here from the phone's own clock.
String _dayKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The period id a board of [scope] is showing, as of [today].
String periodIdFor(LeaderboardScope scope, {DateTime? today}) {
  final dayKey = _dayKey(today ?? DateTime.now());
  return switch (scope) {
    LeaderboardScope.week => isoWeekIdOf(dayKey),
    LeaderboardScope.month => monthIdOf(dayKey),
  };
}

/// Whether the signed-in user has taken themselves off the boards.
///
/// False while it is loading and for a signed-out session: the switch reads as
/// off until the profile says otherwise, which is the state it is in for
/// everybody who has never touched it.
final leaderboardOptOutProvider = StreamProvider<bool>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(false);
  return ref.watch(leaderboardRepositoryProvider).watchOptOut(userId);
});

/// What a board is asked for: a week or a month, ranked on one figure.
typedef BoardRequest = ({LeaderboardScope scope, LeaderboardMetric metric});

/// One board, built from the viewer's following list.
///
/// Two bounded steps: the people the viewer follows plus the viewer, capped at
/// [kLeaderboardLimit] — which is what keeps the number of entry reads fixed
/// however many accounts somebody follows — and then their entries for the
/// period, ten per query (see the repository for why ten). Names and faces are
/// not read here; each row asks `userProfileProvider` for its own.
///
/// A future rather than a stream. A leaderboard is something you open and read,
/// not something that has to move under your thumb, and a live listener per
/// chunk would be five sockets for figures that change a few times a day.
/// Pulling down re-reads it.
final leaderboardProvider =
    FutureProvider.family<LeaderboardBoard, BoardRequest>((ref, request) async {
  if (!ref.watch(leaderboardsEnabledProvider)) return LeaderboardBoard.empty;

  final viewerId = ref.watch(currentUserIdProvider);
  if (viewerId == null) return LeaderboardBoard.empty;

  final following = ref.watch(followingIdsProvider).valueOrNull ?? const {};
  // The viewer is on their own board whether or not they follow themselves, and
  // they are counted inside the cap rather than added past it.
  final userIds = <String>{viewerId, ...following}
      .take(kLeaderboardLimit)
      .toList(growable: false);

  final entries = await ref.watch(leaderboardRepositoryProvider).fetchEntries(
        userIds: userIds,
        periodId: periodIdFor(request.scope),
      );

  return buildBoard(
    entries: entries,
    metric: request.metric,
    viewerId: viewerId,
  );
});

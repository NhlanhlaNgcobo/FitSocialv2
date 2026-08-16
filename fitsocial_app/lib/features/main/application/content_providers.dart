import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/reactions/fit_reaction.dart';
import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../data/content_repository.dart';
import '../data/content_repository_contract.dart';
import '../domain/app_models.dart';
import '../domain/explore_models.dart';
import '../domain/meal_tracking.dart';
import '../domain/progress_models.dart';

// ---------------------------------------------------------------------------
// Feed posts — StateNotifier for optimistic like toggling
// ---------------------------------------------------------------------------

class FeedPostsNotifier extends StateNotifier<AsyncValue<HomeFeed>> {
  FeedPostsNotifier(this._repository, this._profile)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final ContentRepository _repository;
  final UserProfileDraft? _profile;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    final loaded =
        await AsyncValue.guard(() => _repository.getFeedPosts(_profile));

    // The feed can be invalidated — by following someone, by logging an
    // activity — while a load is still in the air, which disposes this
    // notifier and hands the work to a fresh one. Writing the late result
    // then throws, so the abandoned load simply stops here.
    if (!mounted) return;
    state = loaded;
  }

  Future<void> refresh() => _load();

  /// Optimistic reaction — updates the single post in-place, then syncs.
  ///
  /// Pass null to take the reaction back. The card has to answer the tap on
  /// the same frame; a round trip before the emoji changes would make the
  /// whole tray feel broken.
  Future<void> setReaction(
    String postId,
    String userId,
    FitReaction? reaction,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(current.withPosts(current.posts.map((post) {
      if (post.id != postId) return post;
      return _withReaction(post, userId, reaction);
    }).toList()));

    try {
      await _repository.setPostReaction(
        postId,
        userId,
        reaction,
        profile: _profile,
      );
    } catch (_) {
      // Roll back on error — the bar reads from this state, so the reaction
      // simply springs back to what it was.
      state = AsyncValue.data(current);
    }
  }

  /// [post] with [userId]'s reaction set to [reaction], counters and all.
  ///
  /// Mirrors what the transaction does on the server so the optimistic frame
  /// and the one that arrives afterwards agree: the total moves only when
  /// someone joins or leaves, never when they merely change their mind.
  static FeedPost _withReaction(
    FeedPost post,
    String userId,
    FitReaction? reaction,
  ) {
    final previous = post.reactionOf(userId);
    if (previous == reaction) return post;

    final likedBy = List<String>.from(post.likedBy)..remove(userId);
    final reactionsBy = Map<FitReaction, int>.from(post.reactions.counts);
    final by = Map<String, FitReaction>.from(post.reactionsBy)..remove(userId);

    if (previous != null) {
      final left = (reactionsBy[previous] ?? 1) - 1;
      if (left > 0) {
        reactionsBy[previous] = left;
      } else {
        reactionsBy.remove(previous);
      }
    }
    if (reaction != null) {
      likedBy.add(userId);
      by[userId] = reaction;
      reactionsBy[reaction] = (reactionsBy[reaction] ?? 0) + 1;
    }

    final total = (post.likes - (previous == null ? 0 : 1)) +
        (reaction == null ? 0 : 1);

    return post.copyWith(
      likedBy: likedBy,
      likes: total,
      reactionsBy: by,
      reactions: FitReactionSummary(counts: reactionsBy, total: total),
    );
  }

  /// Drops a post from the in-memory feed after it has been deleted on the
  /// server, so the card disappears immediately instead of waiting for a
  /// refresh.
  void removePost(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(
      current.withPosts(
        current.posts
            .where((post) => post.id != postId)
            .toList(growable: false),
      ),
    );
  }

  /// Bump the comment count locally after a comment is posted.
  void incrementCommentCount(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(current.withPosts(current.posts.map((p) {
      if (p.id != postId) return p;
      return p.copyWith(comments: p.comments + 1);
    }).toList()));
  }
}

final feedPostsProvider =
    StateNotifierProvider<FeedPostsNotifier, AsyncValue<HomeFeed>>((ref) {
  final profile = ref.watch(appSessionProvider).profile;
  final repository = ref.watch(contentRepositoryProvider);
  return FeedPostsNotifier(repository, profile);
});

// ---------------------------------------------------------------------------
// Comments — family provider keyed by post ID (one-shot fetch)
// ---------------------------------------------------------------------------

final commentsProvider =
    FutureProvider.family<List<Comment>, String>((ref, postId) {
  return ref.watch(contentRepositoryProvider).getComments(postId);
});

// ---------------------------------------------------------------------------
// NEW: Real-time social action streams
// ---------------------------------------------------------------------------

/// Watches which reaction the active user has given a post.
/// Null when they have given none, and when nobody is signed in.
final postReactionProvider =
    StreamProvider.family<FitReaction?, String>((ref, postId) {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return Stream.value(null);
  return ref
      .watch(contentRepositoryProvider)
      .watchPostReaction(postId, userId);
});

/// Watches whether the active user has bookmarked a specific post.
/// Falls back to `false` when no user is signed in.
final postBookmarkStatusProvider =
    StreamProvider.family<bool, String>((ref, postId) {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return Stream.value(false);
  return ref
      .watch(contentRepositoryProvider)
      .watchBookmarkStatus(postId, userId);
});

/// Real-time stream of comments for a given post, ordered by createdAt asc.
final commentsStreamProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  return ref.watch(contentRepositoryProvider).watchComments(postId);
});

// ---------------------------------------------------------------------------
// Existing providers (unchanged)
// ---------------------------------------------------------------------------

final progressMetricsProvider = FutureProvider<List<ProgressMetric>>((ref) {
  return ref.watch(contentRepositoryProvider).getProgressMetrics();
});

/// Days a week the user is aiming to train.
final weeklyGoalDaysProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(contentRepositoryProvider).getWeeklyGoalDays();
});

/// Every run and workout the signed-in user has logged, newest first.
///
/// The single read behind the whole Progress tab — the streak grid, the
/// overview totals and the session list are all views onto this one list, so
/// paging between periods or ranges costs nothing.
///
/// autoDispose because everything derived from it is anchored to "today": a
/// cached result outlives the day it was built for, and the grid would still
/// be showing yesterday's week after midnight. Logging an activity also
/// invalidates it — see [ActivityActions].
final activitySessionsProvider =
    FutureProvider.autoDispose<List<ActivitySession>>((ref) {
  return ref.watch(contentRepositoryProvider).getActivitySessions();
});

/// The gap-filled run/workout calendar behind the streak grid.
///
/// The window is derived from the range here rather than in the widget so the
/// data and the rendered grid can never disagree about where it starts.
final activityCalendarProvider = FutureProvider.autoDispose
    .family<ActivityCalendar, ActivityRange>((ref, range) async {
  final sessions = await ref.watch(activitySessionsProvider.future);
  final today = DateTime.now();

  // Sessions collapse to per-day counts here: the grid asks "did I train that
  // day", not "what did I do".
  final byDay = <DateTime, ActivityDay>{};
  for (final session in sessions) {
    final existing = byDay[session.day];
    byDay[session.day] = ActivityDay(
      date: session.day,
      runs: (existing?.runs ?? 0) + (session.kind == ActivityKind.run ? 1 : 0),
      workouts: (existing?.workouts ?? 0) +
          (session.kind == ActivityKind.workout ? 1 : 0),
    );
  }

  return ActivityCalendar.fromLoggedDays(
    range: range,
    logged: byDay.values.toList(growable: false),
    today: today,
  );
});

/// The four headline numbers for [window], against the window before it.
final progressOverviewProvider = FutureProvider.autoDispose
    .family<ProgressOverview, ProgressWindow>((ref, window) async {
  final sessions = await ref.watch(activitySessionsProvider.future);
  final goal = await ref.watch(weeklyGoalDaysProvider.future);
  return ProgressOverview.from(
    sessions: sessions,
    window: window,
    weeklyGoalDays: goal,
  );
});

/// The sessions inside [window], newest first.
final windowSessionsProvider = FutureProvider.autoDispose
    .family<List<ActivitySession>, ProgressWindow>((ref, window) async {
  final sessions = await ref.watch(activitySessionsProvider.future);
  return sessions
      .where((session) => window.contains(session.startedAt))
      .toList(growable: false);
});

// ---------------------------------------------------------------------------
// Meal tracking — the logged meals, the targets, and a window's totals
// ---------------------------------------------------------------------------

/// Every meal the user has logged, newest first.
///
/// The single read behind the whole tracking page: the macro summary and the
/// meal list are both views onto it, and switching between Day, Week and Month
/// is a filter rather than another query.
///
/// autoDispose for the same reason as [activitySessionsProvider] — everything
/// derived from it is anchored to "today", and a cached list would still be
/// reporting yesterday's totals after midnight.
final loggedMealsProvider =
    FutureProvider.autoDispose<List<LoggedMeal>>((ref) {
  return ref.watch(contentRepositoryProvider).getLoggedMeals();
});

/// The user's daily macro targets. Not autoDispose: these change rarely, and
/// they are the denominator on every bar on the page.
final macroGoalsProvider = FutureProvider<MacroGoals>((ref) {
  ref.watch(appSessionProvider);
  return ref.watch(contentRepositoryProvider).getMacroGoals();
});

/// Everything the tracking page reports for one window.
final mealWindowSummaryProvider = FutureProvider.autoDispose
    .family<MealWindowSummary, ProgressWindow>((ref, window) async {
  final meals = await ref.watch(loggedMealsProvider.future);
  final goals = await ref.watch(macroGoalsProvider.future);
  return MealWindowSummary.from(meals: meals, window: window, goals: goals);
});

/// Following / Followers / Likes for one profile. Keyed by user id so the
/// signed-in user's header and someone else's share the same code path.
final profileStatsProvider =
    FutureProvider.family<List<ProfileStat>, String>((ref, userId) {
  // The header builds before the uid resolves. An empty id is not a document
  // path Firestore accepts, so it never reaches the repository.
  if (userId.isEmpty) return Future.value(const []);
  return ref.watch(contentRepositoryProvider).getProfileStats(userId);
});

/// One public profile by id, for the other-user profile screen.
final userProfileProvider =
    FutureProvider.family<UserSearchResult?, String>((ref, userId) {
  if (userId.isEmpty) return Future.value(null);
  return ref.watch(contentRepositoryProvider).fetchUserProfile(userId);
});

// ---------------------------------------------------------------------------
// Per-user post queries (profile grids)
// ---------------------------------------------------------------------------

/// One post by id. Only reached when the detail screen was opened without the
/// post already in hand — a tap from a grid passes the loaded post straight
/// through instead.
final postProvider = FutureProvider.family<FeedPost?, String>((ref, postId) {
  if (postId.isEmpty) return Future.value(null);
  return ref.watch(contentRepositoryProvider).fetchPost(postId);
});

/// Every post authored by the given user id, newest first.
final userPostsProvider =
    FutureProvider.family<List<FeedPost>, String>((ref, userId) {
  return ref.watch(contentRepositoryProvider).fetchUserPosts(userId);
});

/// Only the given user's posts that carry an uploaded photo, newest first.
final userMediaPostsProvider =
    FutureProvider.family<List<FeedPost>, String>((ref, userId) {
  return ref.watch(contentRepositoryProvider).fetchUserMediaPosts(userId);
});

/// Convenience: the signed-in user's uid, or null when unauthenticated.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(appSessionProvider);
  return FirebaseAuth.instance.currentUser?.uid;
});

// ---------------------------------------------------------------------------
// Explore — search and trending
// ---------------------------------------------------------------------------

/// The active Explore search term. Empty means "show trending".
final userSearchQueryProvider = StateProvider<String>((ref) => '');

/// Profiles matching the current search term.
final userSearchResultsProvider =
    FutureProvider.family<List<UserSearchResult>, String>((ref, query) {
  if (query.trim().isEmpty) return Future.value(const []);
  return ref.watch(contentRepositoryProvider).searchUsers(query);
});

/// Accounts matching the `@` currently being typed in a composer.
///
/// autoDispose because the key is a half-typed word: every keystroke that
/// survives the debounce mints a new one, and keeping them all would grow a
/// cache nobody reads twice. Keyed on the prefix rather than held in the widget
/// so the comment box and the caption field share one set of results.
final mentionSuggestionsProvider = FutureProvider.autoDispose
    .family<List<UserSearchResult>, String>((ref, prefix) {
  return ref.watch(contentRepositoryProvider).suggestMentions(prefix);
});

/// The Explore grid, ranked by engagement against age.
///
/// autoDispose because the ranking is computed against "now": a cached list
/// outlives the hour it was scored in, and a user returning to the tab
/// tomorrow would still be looking at yesterday's ordering. Re-ranking costs
/// one query per visit.
final trendingPostsProvider = FutureProvider.autoDispose<List<FeedPost>>((ref) {
  return ref.watch(contentRepositoryProvider).fetchTrendingPosts();
});

/// Which category chip is active above the Explore grid.
final exploreFilterProvider =
    StateProvider<ExploreFilter>((ref) => ExploreFilter.all);

// ---------------------------------------------------------------------------
// Follow graph
// ---------------------------------------------------------------------------

/// Whether the signed-in user follows [targetUserId]. Keyed by target only —
/// the follower is always the current user.
final isFollowingProvider =
    StreamProvider.family<bool, String>((ref, targetUserId) {
  final currentUserId = ref.watch(currentUserIdProvider);
  if (currentUserId == null) return Stream.value(false);
  return ref
      .watch(contentRepositoryProvider)
      .watchIsFollowing(currentUserId, targetUserId);
});

/// Everyone the signed-in user follows, live.
///
/// The audience for anything scoped to the follow graph. Kept as a stream so
/// following someone changes what they can see immediately, rather than at the
/// next load.
final followingIdsProvider = StreamProvider<Set<String>>((ref) {
  final currentUserId = ref.watch(currentUserIdProvider);
  if (currentUserId == null) return Stream.value(const <String>{});
  return ref.watch(contentRepositoryProvider).watchFollowingIds(currentUserId);
});

/// Whether the signed-in user has push notifications turned on for
/// [targetUserId]'s activity.
final userNotificationsProvider =
    StreamProvider.family<bool, String>((ref, targetUserId) {
  final currentUserId = ref.watch(currentUserIdProvider);
  if (currentUserId == null) return Stream.value(false);
  return ref
      .watch(contentRepositoryProvider)
      .watchUserNotifications(currentUserId, targetUserId);
});

/// Turns the per-user notification marker on or off. The provider above is a
/// live stream, so nothing needs invalidating afterwards.
final userNotificationActionsProvider =
    Provider<Future<void> Function(String, {required bool enabled})>((ref) {
  return (String targetUserId, {required bool enabled}) {
    final currentUserId = ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      throw StateError('You must be signed in to change notifications.');
    }
    return ref
        .read(contentRepositoryProvider)
        .setUserNotifications(currentUserId, targetUserId, enabled: enabled);
  };
});

/// Follow/unfollow actions plus the cache invalidation they imply.
class FollowActions {
  const FollowActions(this._ref);

  final Ref _ref;

  Future<void> toggle(String targetUserId, {required bool isFollowing}) async {
    final currentUserId = _ref.read(currentUserIdProvider);
    if (currentUserId == null) {
      throw StateError('You must be signed in to follow people.');
    }

    final repository = _ref.read(contentRepositoryProvider);
    if (isFollowing) {
      await repository.unfollowUser(currentUserId, targetUserId);
    } else {
      // The session profile names the follower on the notification this
      // raises, sparing the repository a read of a profile the app already
      // has in hand.
      await repository.followUser(
        currentUserId,
        targetUserId,
        profile: _ref.read(appSessionProvider).profile,
      );
    }

    // isFollowingProvider is a live stream and updates itself; the profile
    // header counts are one-shot reads and need refreshing.
    _ref.invalidate(profileStatsProvider);

    // The home feed is built from the follow graph, so following someone is
    // exactly the moment it stops being right. Rebuilt rather than patched:
    // the new author's back catalogue has to be merged in by date, which is
    // the query's job and not something the list can do to itself.
    _ref.invalidate(feedPostsProvider);
  }
}

final followActionsProvider = Provider<FollowActions>((ref) {
  return FollowActions(ref);
});

// ---------------------------------------------------------------------------
// Achievements — XP, level, streak and badge progress
// ---------------------------------------------------------------------------

/// Aggregated achievements for the signed-in user. Watches the session profile
/// so it recomputes after sign-in/out, and is invalidated by [ActivityActions]
/// whenever a workout, run or meal is logged.
final achievementsProvider = FutureProvider<AchievementsData>((ref) {
  // Depend on the session so a sign-out/sign-in swaps the underlying user.
  ref.watch(appSessionProvider);

  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) {
    throw StateError('You must be signed in to view achievements.');
  }
  return ref.watch(contentRepositoryProvider).fetchUserAchievements(userId);
});

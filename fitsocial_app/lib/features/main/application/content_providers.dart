import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../data/content_repository.dart';
import '../data/content_repository_contract.dart';
import '../domain/app_models.dart';
import '../domain/explore_models.dart';

// ---------------------------------------------------------------------------
// Feed posts — StateNotifier for optimistic like toggling
// ---------------------------------------------------------------------------

class FeedPostsNotifier extends StateNotifier<AsyncValue<List<FeedPost>>> {
  FeedPostsNotifier(this._repository, this._profile)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final ContentRepository _repository;
  final UserProfileDraft? _profile;

  Future<void> _load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.getFeedPosts(_profile));
  }

  Future<void> refresh() => _load();

  /// Optimistic like toggle — updates the single post in-place, then syncs.
  Future<void> toggleLike(String postId, String userId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    // Optimistic update
    state = AsyncValue.data(current.map((p) {
      if (p.id != postId) return p;
      final liked = p.likedBy.contains(userId);
      final newLikedBy = liked
          ? (List<String>.from(p.likedBy)..remove(userId))
          : [...p.likedBy, userId];
      return p.copyWith(
        likedBy: newLikedBy,
        likes: newLikedBy.length,
      );
    }).toList());

    // Sync to Firestore
    try {
      await _repository.toggleLike(postId, userId);
    } catch (_) {
      // Roll back on error
      state = AsyncValue.data(current);
    }
  }

  /// Drops a post from the in-memory feed after it has been deleted on the
  /// server, so the card disappears immediately instead of waiting for a
  /// refresh.
  void removePost(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(
      current.where((post) => post.id != postId).toList(growable: false),
    );
  }

  /// Bump the comment count locally after a comment is posted.
  void incrementCommentCount(String postId) {
    final current = state.valueOrNull;
    if (current == null) return;

    state = AsyncValue.data(current.map((p) {
      if (p.id != postId) return p;
      return p.copyWith(comments: p.comments + 1);
    }).toList());
  }
}

final feedPostsProvider =
    StateNotifierProvider<FeedPostsNotifier, AsyncValue<List<FeedPost>>>((ref) {
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

/// Watches whether the active user has liked a specific post.
/// Falls back to `false` when no user is signed in.
final postLikeStatusProvider =
    StreamProvider.family<bool, String>((ref, postId) {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return Stream.value(false);
  return ref.watch(contentRepositoryProvider).watchPostLikeStatus(postId, userId);
});

/// Watches whether the active user has bookmarked a specific post.
/// Falls back to `false` when no user is signed in.
final postBookmarkStatusProvider =
    StreamProvider.family<bool, String>((ref, postId) {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return Stream.value(false);
  return ref.watch(contentRepositoryProvider).watchBookmarkStatus(postId, userId);
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

/// The gap-filled run/workout calendar behind the progress grid.
///
/// The window is derived from the range here rather than in the widget so the
/// query and the rendered grid can never disagree about where it starts.
///
/// autoDispose because the window is anchored to "today": a cached calendar
/// outlives the day it was built for, and would still be showing yesterday's
/// week after midnight. Re-reading on each visit to the tab costs two small
/// queries. Logging an activity also invalidates this — see [ActivityActions].
final activityCalendarProvider = FutureProvider.autoDispose
    .family<ActivityCalendar, ActivityRange>((ref, range) async {
  final today = DateTime.now();
  final start = ActivityCalendar.startOfWindow(range, today);
  final logged = await ref.watch(contentRepositoryProvider).getActivityDays(start);
  return ActivityCalendar.fromLoggedDays(
    range: range,
    logged: logged,
    today: today,
  );
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
final postProvider =
    FutureProvider.family<FeedPost?, String>((ref, postId) {
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

/// The Explore grid, ranked by engagement against age.
///
/// autoDispose because the ranking is computed against "now": a cached list
/// outlives the hour it was scored in, and a user returning to the tab
/// tomorrow would still be looking at yesterday's ordering. Re-ranking costs
/// one query per visit.
final trendingPostsProvider =
    FutureProvider.autoDispose<List<FeedPost>>((ref) {
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
      await repository.followUser(currentUserId, targetUserId);
    }

    // isFollowingProvider is a live stream and updates itself; the profile
    // header counts are one-shot reads and need refreshing.
    _ref.invalidate(profileStatsProvider);
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../../auth/domain/auth_models.dart';
import '../data/content_repository.dart';
import '../data/content_repository_contract.dart';
import '../domain/app_models.dart';

final storyItemsProvider = FutureProvider<List<StoryItem>>((ref) {
  final profile = ref.watch(appSessionProvider).profile;
  final repository = ref.watch(contentRepositoryProvider);
  return repository.getStories(profile);
});

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

final summaryMetricsProvider = FutureProvider<List<SummaryMetric>>((ref) {
  return ref.watch(contentRepositoryProvider).getSummaryMetrics();
});

final progressMetricsProvider = FutureProvider<List<ProgressMetric>>((ref) {
  return ref.watch(contentRepositoryProvider).getProgressMetrics();
});

final workoutPlaylistsProvider =
    FutureProvider.family<List<WorkoutPlaylist>, WorkoutType>(
        (ref, workoutType) {
  return ref.watch(contentRepositoryProvider).getWorkoutPlaylists(workoutType);
});

final podcastRecommendationsProvider =
    FutureProvider<List<PodcastRecommendation>>((ref) {
  return ref.watch(contentRepositoryProvider).getPodcastRecommendations();
});

final profileStatsProvider = FutureProvider<List<ProfileStat>>((ref) {
  return ref.watch(contentRepositoryProvider).getProfileStats();
});

// ---------------------------------------------------------------------------
// Per-user post queries (profile grids)
// ---------------------------------------------------------------------------

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

/// Most-liked posts across the community.
final trendingPostsProvider = FutureProvider<List<FeedPost>>((ref) {
  return ref.watch(contentRepositoryProvider).fetchTrendingPosts();
});

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

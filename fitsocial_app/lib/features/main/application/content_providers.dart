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
// Comments — family provider keyed by post ID
// ---------------------------------------------------------------------------

final commentsProvider =
    FutureProvider.family<List<Comment>, String>((ref, postId) {
  return ref.watch(contentRepositoryProvider).getComments(postId);
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

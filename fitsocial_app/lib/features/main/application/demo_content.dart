import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/app_session.dart';
import '../data/content_repository.dart';
import '../domain/app_models.dart';

final storyItemsProvider = FutureProvider<List<StoryItem>>((ref) {
  final profile = ref.watch(appSessionProvider).profile;
  final repository = ref.watch(contentRepositoryProvider);
  return repository.getStories(profile);
});

final feedPostsProvider = FutureProvider<List<FeedPost>>((ref) {
  final profile = ref.watch(appSessionProvider).profile;
  final repository = ref.watch(contentRepositoryProvider);
  return repository.getFeedPosts(profile);
});

final summaryMetricsProvider = FutureProvider<List<SummaryMetric>>((ref) {
  return ref.watch(contentRepositoryProvider).getSummaryMetrics();
});

final progressMetricsProvider = FutureProvider<List<ProgressMetric>>((ref) {
  return ref.watch(contentRepositoryProvider).getProgressMetrics();
});

final workoutPlaylistsProvider =
    FutureProvider.family<List<WorkoutPlaylist>, WorkoutType>((ref, workoutType) {
  return ref.watch(contentRepositoryProvider).getWorkoutPlaylists(workoutType);
});

final podcastRecommendationsProvider = FutureProvider<List<PodcastRecommendation>>((ref) {
  return ref.watch(contentRepositoryProvider).getPodcastRecommendations();
});

final profileStatsProvider = FutureProvider<List<ProfileStat>>((ref) {
  return ref.watch(contentRepositoryProvider).getProfileStats();
});

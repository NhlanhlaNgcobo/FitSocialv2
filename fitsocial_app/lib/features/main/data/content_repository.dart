import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/bootstrap/bootstrap_status.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/app_models.dart';
import 'content_repository_contract.dart';
import 'firestore_content_repository.dart';
import '../../../shared/widgets/brand_image_tile.dart';

class MockContentRepository implements ContentRepository {
  final List<FeedPost> _userPosts = <FeedPost>[];
  int _workoutsLogged = 4;
  int _mealsLogged = 11;
  int _postsCount = 32;

  @override
  Future<List<StoryItem>> getStories(UserProfileDraft? profile) async {
    final displayName = profile?.displayName ?? 'Neo Motion';
    final firstName = displayName.split(' ').first;
    final initials = _initials(displayName);

    return [
      StoryItem(
        name: 'Your Story',
        initials: initials,
        visualTile: AppVisualTile.heroPortrait,
        isOwnStory: true,
      ),
      StoryItem(
        name: firstName,
        initials: initials,
        visualTile: AppVisualTile.coastalRunner,
      ),
      const StoryItem(
        name: 'Lerato',
        initials: 'LK',
        visualTile: AppVisualTile.womanRunner,
      ),
      const StoryItem(
        name: 'Mike',
        initials: 'MJ',
        visualTile: AppVisualTile.gymFlex,
      ),
      const StoryItem(
        name: 'Zan',
        initials: 'ZN',
        visualTile: AppVisualTile.groupTraining,
      ),
    ];
  }

  @override
  Future<List<FeedPost>> getFeedPosts(UserProfileDraft? profile) async {
    return [
      ..._userPosts,
      FeedPost(
        userName: profile?.displayName ?? 'Neo M.',
        activity: 'Morning Run',
        caption: 'Great way to start the day.',
        metricLabels: const ['5.02 km', '28:16', '05:37 /km'],
        timestamp: '2h ago',
        likes: 124,
        comments: 12,
        backgroundColors: const [Color(0xFF7A4D2E), Color(0xFF121212)],
        visualTile: AppVisualTile.coastalRunner,
      ),
      const FeedPost(
        userName: 'Lerato K.',
        activity: 'Push Day',
        caption: 'Consistency stacking up one session at a time.',
        metricLabels: ['52 min', '6 moves', '520 kcal'],
        timestamp: '3h ago',
        likes: 87,
        comments: 9,
        backgroundColors: [Color(0xFF422919), Color(0xFF0E0E0E)],
        visualTile: AppVisualTile.gymFlex,
      ),
      const FeedPost(
        userName: 'Chris van Wyk',
        activity: 'Recovery Meal',
        caption: 'Keeping it simple: protein, carbs, and healthy fats.',
        metricLabels: ['520 kcal', '45g protein', '18g fat'],
        timestamp: '5h ago',
        likes: 63,
        comments: 6,
        backgroundColors: [Color(0xFF5A3B28), Color(0xFF141414)],
        visualTile: AppVisualTile.mealBowl,
      ),
    ];
  }

  @override
  Future<List<SummaryMetric>> getSummaryMetrics() async {
    return [
      SummaryMetric(label: 'This week', value: '$_workoutsLogged workouts'),
      SummaryMetric(label: 'Meals logged', value: '$_mealsLogged meals'),
    ];
  }

  @override
  Future<List<ProgressMetric>> getProgressMetrics() async {
    return const [
      ProgressMetric(
        label: 'Workouts',
        value: '12',
        delta: '+20% vs last 30 days',
        chartBars: [0.28, 0.55, 0.7, 0.48, 0.82, 0.62, 0.9, 0.58, 0.74],
      ),
      ProgressMetric(
        label: 'Calories Burned',
        value: '4,560 kcal',
        delta: '+15% vs last 30 days',
        chartBars: [0.2, 0.25, 0.4, 0.52, 0.45, 0.63, 0.78, 0.7, 0.88],
      ),
      ProgressMetric(
        label: 'Active Minutes',
        value: '1,980 min',
        delta: '+18% vs last 30 days',
        chartBars: [0.15, 0.34, 0.44, 0.39, 0.57, 0.52, 0.71, 0.69, 0.87],
      ),
    ];
  }

  @override
  Future<List<WorkoutPlaylist>> getWorkoutPlaylists(
      WorkoutType workoutType) async {
    switch (workoutType) {
      case WorkoutType.strength:
        return const [
          WorkoutPlaylist(
            title: 'Heavy Sets SA',
            subtitle: 'Hip-hop, amapiano, and hard-hitting gym anthems',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.strength,
            durationLabel: '1h 18m',
            trackCount: 22,
            backgroundColors: [Color(0xFF53260C), Color(0xFF0F0F0F)],
            visualTile: AppVisualTile.gymFlex,
          ),
          WorkoutPlaylist(
            title: 'Iron Focus',
            subtitle: 'Apple Music mix for upper-body and leg day intensity',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.strength,
            durationLabel: '56m',
            trackCount: 16,
            backgroundColors: [Color(0xFF2D1D1A), Color(0xFF090909)],
            visualTile: AppVisualTile.groupTraining,
          ),
        ];
      case WorkoutType.cardio:
        return const [
          WorkoutPlaylist(
            title: 'Cardio Burn Loop',
            subtitle: 'Fast BPM tracks to keep your heart rate up',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.cardio,
            durationLabel: '48m',
            trackCount: 14,
            backgroundColors: [Color(0xFF1F3540), Color(0xFF0B0B0B)],
            visualTile: AppVisualTile.womanRunner,
          ),
          WorkoutPlaylist(
            title: 'Move Without Ads',
            subtitle: 'Premium Apple Music cardio picks for treadmill days',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.cardio,
            durationLabel: '1h 02m',
            trackCount: 19,
            backgroundColors: [Color(0xFF40301E), Color(0xFF0D0D0D)],
            visualTile: AppVisualTile.coastalRunner,
          ),
        ];
      case WorkoutType.hiit:
        return const [
          WorkoutPlaylist(
            title: 'HIIT Ignition',
            subtitle: 'Explosive drop-heavy mix for interval sessions',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.hiit,
            durationLabel: '37m',
            trackCount: 12,
            backgroundColors: [Color(0xFF4C1C16), Color(0xFF111111)],
            visualTile: AppVisualTile.groupTraining,
          ),
          WorkoutPlaylist(
            title: 'No-Skip Intervals',
            subtitle: 'Apple Music energy stack for circuits and finishers',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.hiit,
            durationLabel: '43m',
            trackCount: 13,
            backgroundColors: [Color(0xFF4E2C12), Color(0xFF090909)],
            visualTile: AppVisualTile.gymFlex,
          ),
        ];
      case WorkoutType.run:
        return const [
          WorkoutPlaylist(
            title: 'Sunrise Run Cape Town',
            subtitle: 'Rhythmic pace-setters for road and coastal runs',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.run,
            durationLabel: '1h 09m',
            trackCount: 21,
            backgroundColors: [Color(0xFF3F2C1A), Color(0xFF101010)],
            visualTile: AppVisualTile.coastalRunner,
          ),
          WorkoutPlaylist(
            title: 'Runners Flow',
            subtitle: 'Apple Music endurance mix with smooth build and finish',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.run,
            durationLabel: '54m',
            trackCount: 17,
            backgroundColors: [Color(0xFF1F2F34), Color(0xFF0C0C0C)],
            visualTile: AppVisualTile.womanRunner,
          ),
        ];
      case WorkoutType.yoga:
        return const [
          WorkoutPlaylist(
            title: 'Reset & Recover',
            subtitle: 'Breath-led calm for yoga and mobility work',
            provider: MusicProviderService.spotify,
            workoutType: WorkoutType.yoga,
            durationLabel: '42m',
            trackCount: 11,
            backgroundColors: [Color(0xFF213126), Color(0xFF0B0B0B)],
            visualTile: AppVisualTile.heroPortrait,
          ),
          WorkoutPlaylist(
            title: 'Deep Stretch',
            subtitle: 'Apple Music wind-down playlist for recovery sessions',
            provider: MusicProviderService.appleMusic,
            workoutType: WorkoutType.yoga,
            durationLabel: '39m',
            trackCount: 10,
            backgroundColors: [Color(0xFF2B271E), Color(0xFF0A0A0A)],
            visualTile: AppVisualTile.mealBowl,
          ),
        ];
    }
  }

  @override
  Future<List<PodcastRecommendation>> getPodcastRecommendations() async {
    return const [
      PodcastRecommendation(
        title: 'Mindset Reset',
        host: 'Lebo M.',
        provider: MusicProviderService.spotify,
        category: PodcastCategory.mindset,
        episodeTitle: 'How to stay consistent when motivation dips',
        durationLabel: '28m',
        backgroundColors: [Color(0xFF24322C), Color(0xFF0D0D0D)],
        visualTile: AppVisualTile.heroPortrait,
      ),
      PodcastRecommendation(
        title: 'Built With Discipline',
        host: 'Chris van Wyk',
        provider: MusicProviderService.appleMusic,
        category: PodcastCategory.discipline,
        episodeTitle: 'Training your habits before your body',
        durationLabel: '34m',
        backgroundColors: [Color(0xFF3E2A1E), Color(0xFF0D0D0D)],
        visualTile: AppVisualTile.gymFlex,
      ),
      PodcastRecommendation(
        title: 'Recover Better',
        host: 'Dr. Naledi K.',
        provider: MusicProviderService.spotify,
        category: PodcastCategory.recovery,
        episodeTitle: 'Sleep, stress, and real progress',
        durationLabel: '22m',
        backgroundColors: [Color(0xFF22313D), Color(0xFF0C0C0C)],
        visualTile: AppVisualTile.mealBowl,
      ),
      PodcastRecommendation(
        title: 'Growth Playbook',
        host: 'Aiden Rossouw',
        provider: MusicProviderService.appleMusic,
        category: PodcastCategory.business,
        episodeTitle: 'What self-improvement looks like off the gym floor',
        durationLabel: '31m',
        backgroundColors: [Color(0xFF3D241E), Color(0xFF0B0B0B)],
        visualTile: AppVisualTile.groupTraining,
      ),
    ];
  }

  @override
  Future<List<ProfileStat>> getProfileStats() async {
    return [
      ProfileStat(label: 'Posts', value: '$_postsCount'),
      const ProfileStat(label: 'Followers', value: '256'),
      const ProfileStat(label: 'Following', value: '180'),
    ];
  }

  @override
  Future<ActivitySaveResult> saveWorkout(
    UserProfileDraft? profile,
    WorkoutLogDraft draft,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _workoutsLogged++;
    if (!draft.shareToFeed) {
      return const ActivitySaveResult(message: 'Workout saved.');
    }

    final post = _buildPost(
      profile: profile,
      activity: draft.title.trim().isEmpty ? 'Workout' : draft.title.trim(),
      caption: 'Logged ${draft.exercises.length} exercises.',
      metricLabels: [
        draft.duration,
        draft.calories,
        '${draft.exercises.length} moves'
      ],
      visualTile: AppVisualTile.gymFlex,
    );
    _insertPost(post);
    return ActivitySaveResult(
        message: 'Workout saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> saveRun(
    UserProfileDraft? profile,
    RunLogDraft draft,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _workoutsLogged++;
    if (!draft.shareToFeed) {
      return const ActivitySaveResult(message: 'Run saved.');
    }

    final post = _buildPost(
      profile: profile,
      activity: 'Run',
      caption: 'Finished a ${draft.distanceKm.toStringAsFixed(2)} km run.',
      metricLabels: [
        '${draft.distanceKm.toStringAsFixed(2)} km',
        _formatDuration(draft.elapsed),
        draft.averagePace,
      ],
      visualTile: AppVisualTile.coastalRunner,
    );
    _insertPost(post);
    return ActivitySaveResult(
        message: 'Run saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> saveMeal(
    UserProfileDraft? profile,
    MealLogDraft draft,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _mealsLogged++;
    if (!draft.shareToFeed) {
      return const ActivitySaveResult(message: 'Meal saved.');
    }

    final post = _buildPost(
      profile: profile,
      activity: draft.name.trim().isEmpty ? 'Meal' : draft.name.trim(),
      caption: draft.notes.trim().isEmpty ? 'Meal logged.' : draft.notes.trim(),
      metricLabels: [
        '${draft.calories.trim()} kcal',
        '${draft.protein.trim()}g protein',
        '${draft.fat.trim()}g fat',
      ],
      visualTile: AppVisualTile.mealBowl,
    );
    _insertPost(post);
    return ActivitySaveResult(
        message: 'Meal saved and shared.', createdPost: post);
  }

  @override
  Future<ActivitySaveResult> sharePost(
    UserProfileDraft? profile,
    PostDraft draft,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final caption = draft.caption.trim();
    final post = _buildPost(
      profile: profile,
      activity: 'Status Update',
      caption: caption.isEmpty ? 'Shared a FitSocial update.' : caption,
      metricLabels: const ['Post', 'Community', 'Now'],
      visualTile: AppVisualTile.groupTraining,
    );
    _insertPost(post);
    return ActivitySaveResult(message: 'Post shared.', createdPost: post);
  }

  FeedPost _buildPost({
    required UserProfileDraft? profile,
    required String activity,
    required String caption,
    required List<String> metricLabels,
    required AppVisualTile visualTile,
  }) {
    return FeedPost(
      userName: profile?.displayName ?? 'Neo M.',
      activity: activity,
      caption: caption,
      metricLabels: metricLabels,
      timestamp: 'now',
      likes: 0,
      comments: 0,
      backgroundColors: const [Color(0xFF7A4D2E), Color(0xFF121212)],
      visualTile: visualTile,
    );
  }

  void _insertPost(FeedPost post) {
    _userPosts.insert(0, post);
    _postsCount++;
  }
}

final contentRepository = MockContentRepository();

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  final status = ref.watch(bootstrapStatusProvider);
  if (status.canUseFirebase) {
    return FirestoreContentRepository(FirebaseFirestore.instance);
  }
  return contentRepository;
});

String _initials(String value) {
  final parts = value.trim().split(' ');
  if (parts.length < 2) {
    final first = parts.first;
    if (first.isEmpty) return 'FS';
    final end = first.length > 1 ? 2 : 1;
    return first.substring(0, end).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
